#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to log with timestamp
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check for delete argument
if [ "$1" = "delete" ]; then
    log "${YELLOW}Stopping and removing all containers and volumes...${NC}"
    docker rm -f open-webui >/dev/null 2>&1
    docker volume rm open-webui >/dev/null 2>&1
    docker rm -f ollama >/dev/null 2>&1
    docker volume rm ollama >/dev/null 2>&1
    
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl stop ollama >/dev/null 2>&1
        sudo systemctl disable ollama >/dev/null 2>&1
        sudo rm -f /etc/systemd/system/ollama.service
        sudo systemctl daemon-reload
    fi
    
    log "${GREEN}Cleanup completed${NC}"
    exit 0
fi

# Check system compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MACOS=true
elif grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
fi

# Docker installation based on system type
install_docker() {
    if [[ "$IS_MACOS" == true ]]; then
        if ! command -v docker >/dev/null 2>&1; then
            log "${RED}Please install Docker Desktop for Mac first${NC}"
            exit 1
        fi
    elif [[ "$IS_WSL" == true ]]; then
        if ! command -v docker >/dev/null 2>&1; then
            log "${RED}Please install Docker Desktop for Windows first${NC}"
            exit 1
        fi
    else
        if ! command -v docker >/dev/null 2>&1; then
            log "${BLUE}Installing Docker...${NC}"
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            sudo systemctl enable docker
            sudo systemctl start docker
            log "${YELLOW}Please log out and back in for Docker permissions to take effect${NC}"
        fi
    fi
    if systemctl is-active --quiet docker; then
        log "${GREEN}Docker daemon is running${NC}"
    else
        log "${YELLOW}Starting Docker daemon...${NC}"
        sudo systemctl start docker
        sleep 3
    fi
}

# Ollama installation based on system type
install_ollama() {
    if [[ "$IS_MACOS" == true ]]; then
        if ! command -v ollama >/dev/null 2>&1; then
            log "${BLUE}Installing Ollama for macOS...${NC}"
            curl -fsSL https://ollama.com/install.sh | sh
        fi
    else
        if ! command -v ollama >/dev/null 2>&1; then
            log "${BLUE}Installing Ollama...${NC}"
            curl -fsSL https://ollama.com/install.sh | sh
            
            # Create systemd service only for Linux
            if [[ "$IS_WSL" != true ]] && command -v systemctl >/dev/null 2>&1; then
                create_systemd_service
            fi
        fi
    fi
}

# Function to create systemd service
create_systemd_service() {
    if [ ! -f /etc/systemd/system/ollama.service ]; then
        log "${BLUE}Creating systemd service...${NC}"
        sudo tee /etc/systemd/system/ollama.service > /dev/null << EOF
[Unit]
Description=Ollama Service
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="OLLAMA_HOST=0.0.0.0"
ExecStart=/usr/local/bin/ollama serve
WorkingDirectory=/home/$USER
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        sudo systemctl enable ollama
        sudo systemctl start ollama
    fi
}

# Function to check Docker network
check_docker_network() {
    if ! docker network inspect ollama-network >/dev/null 2>&1; then
        log "${BLUE}Creating Docker network...${NC}"
        docker network create ollama-network >/dev/null 2>&1
    fi
}

# Update deploy_webui function
deploy_webui() {
    check_docker_network
    
    # Remove existing container if it exists
    docker rm -f open-webui >/dev/null 2>&1
    
    # Use host.docker.internal for non-Linux systems
    if [[ "$IS_MACOS" == true ]] || [[ "$IS_WSL" == true ]]; then
        OLLAMA_HOST="host.docker.internal"
        EXTRA_ARGS="--add-host=host.docker.internal:host-gateway"
        PORT_MAPPING="-p 3000:8080"
        WEBUI_PORT="3000"
    else
        # Try network=host first, then fallback to ollama-network if it fails
        if docker run --rm --network=host busybox ping -c 1 localhost >/dev/null 2>&1; then
            OLLAMA_HOST="127.0.0.1"
            EXTRA_ARGS="--network=host"
            PORT_MAPPING=""
            WEBUI_PORT="8080"
        else
            OLLAMA_HOST="localhost"
            EXTRA_ARGS="--network ollama-network"
            PORT_MAPPING="-p 3000:8080"
            WEBUI_PORT="3000"
        fi
    fi
    
    # Select appropriate image tag and environment variables
    if [[ -n "$DOCKER_GPU_ARGS" ]]; then
        IMAGE_TAG="cuda"
        CUDA_ENV="-e NVIDIA_VISIBLE_DEVICES=all -e USE_CUDA_DOCKER=true -e NVIDIA_DRIVER_CAPABILITIES=compute,utility"
    else
        IMAGE_TAG="main"
        CUDA_ENV=""
    fi
    
    # Common environment variables with improved defaults
    ENV_VARS="-e OLLAMA_API_BASE_URL=http://${OLLAMA_HOST}:11434/api \
        -e OLLAMA_API_BASE_URL_BROWSER=http://localhost:11434/api \
        -e AIOHTTP_CLIENT_TIMEOUT=300 \
        -e OLLAMA_ORIGINS=* \
        -e TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC") \
        -e RESET_CONFIG_ON_START=false \
        -e OLLAMA_MODELS_PATH=/root/.ollama/models \
        -e OLLAMA_TIMEOUT=300"
    
    if ! docker run -d \
        --name open-webui \
        --restart always \
        $EXTRA_ARGS \
        ${PORT_MAPPING:-"-p 3000:8080"} \
        $DOCKER_GPU_ARGS \
        $CUDA_ENV \
        $ENV_VARS \
        -v open-webui:/app/backend/data \
        -v ollama:/root/.ollama \
        --memory-swap -1 \
        --shm-size=1g \
        ghcr.io/open-webui/open-webui:${IMAGE_TAG}; then
        log "${RED}Failed to deploy Open WebUI container${NC}"
        return 1
    fi
    
    # Wait for WebUI to be ready
    for i in {1..15}; do
        if curl -s "http://localhost:${WEBUI_PORT}" >/dev/null; then
            log "${GREEN}Open WebUI is ready${NC}"
            return 0
        fi
        log "${YELLOW}Waiting for Open WebUI to start (attempt $i/15)...${NC}"
        sleep 2
    done
    log "${RED}Open WebUI failed to respond after 30 seconds${NC}"
    return 1
}

# Update wait_for_ollama function
wait_for_ollama() {
    log "${BLUE}Waiting for Ollama API...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/version >/dev/null; then
            log "${GREEN}Ollama API is ready${NC}"
            # Verify model pulling capability
            if ollama list >/dev/null 2>&1; then
                return 0
            fi
        fi
        log "${YELLOW}Waiting for Ollama API (attempt $i/30)...${NC}"
        sleep 2
    done
    log "${RED}Ollama API failed to respond after 60 seconds${NC}"
    return 1
}

# Main installation process
install_docker
install_ollama

# Wait for Ollama to be ready
wait_for_ollama

# Pull required models
MODELS=("llama3.2:3b" "qwen2.5-coder:32b" "internlm2")
for model in "${MODELS[@]}"; do
    if ! ollama list | grep -q "^$model\s"; then
        log "${BLUE}Pulling $model model...${NC}"
        if ! ollama pull $model; then
            log "${RED}Failed to pull $model model${NC}"
            continue
        fi
    fi
done

# Deploy Open WebUI with error handling
log "${BLUE}Deploying Open WebUI...${NC}"
HOST_IP=$(ip route get 1 | awk '{print $7}' | head -n 1)

if [ -z "$HOST_IP" ]; then
    log "${RED}Failed to determine host IP address${NC}"
    exit 1
fi

# GPU detection remains the same
if command -v nvidia-smi >/dev/null 2>&1; then
    DOCKER_GPU_ARGS="--gpus all"
    log "${GREEN}GPU support detected and enabled${NC}"
else
    DOCKER_GPU_ARGS=""
    log "${YELLOW}No GPU support detected, running in CPU mode${NC}"
fi

# Deploy with new error handling
if ! deploy_webui; then
    log "${RED}Failed to deploy Open WebUI. Check the logs above for details${NC}"
    exit 1
fi

# Check if running via SSH and provide instructions
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
    log "${GREEN}To access the UI locally, run this command on your local machine:${NC}"
    log "${BLUE}ssh -L ${WEBUI_PORT}:localhost:${WEBUI_PORT} -L 11434:localhost:11434 $(whoami)@$LOCAL_IP${NC}"
    log "${GREEN}Then open http://localhost:${WEBUI_PORT} in your browser${NC}"
else
    log "${GREEN}Web interface available at http://localhost:${WEBUI_PORT}${NC}"
fi 