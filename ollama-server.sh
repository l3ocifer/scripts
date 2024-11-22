#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default image tag
IMAGE_TAG="latest"

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
    
    # Use host networking for Linux systems
    if [[ "$IS_MACOS" == true ]] || [[ "$IS_WSL" == true ]]; then
        OLLAMA_HOST="host.docker.internal"
        EXTRA_ARGS="--add-host=host.docker.internal:host-gateway"
        PORT_MAPPING="-p 3000:8080"
        WEBUI_PORT="3000"
    else
        OLLAMA_HOST="127.0.0.1"
        EXTRA_ARGS="--network host"
        WEBUI_PORT="8080"
    fi
    
    # Common environment variables
    ENV_VARS="-e OLLAMA_API_BASE_URL=http://${OLLAMA_HOST}:11434 \
        -e OLLAMA_API_BASE_URL_BROWSER=http://localhost:11434 \
        -e AIOHTTP_CLIENT_TIMEOUT=300 \
        -e OLLAMA_ORIGINS=* \
        -e TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")"
    
    # Deploy container
    if ! docker run -d \
        --name open-webui \
        --restart always \
        $EXTRA_ARGS \
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
        if curl -s "http://localhost:${WEBUI_PORT}/api/v1/health" >/dev/null; then
            log "${GREEN}Open WebUI is ready${NC}"
            return 0
        fi
        log "${YELLOW}Waiting for Open WebUI to start (attempt $i/15)...${NC}"
        sleep 2
    done
    
    log "${RED}Open WebUI failed to start${NC}"
    return 1
}

# Update wait_for_ollama function
wait_for_ollama() {
    log "${BLUE}Waiting for Ollama API...${NC}"
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/version >/dev/null; then
            log "${GREEN}Ollama API is ready${NC}"
            # Check running models
            if running_models=$(ollama ps 2>/dev/null); then
                log "${GREEN}Ollama is serving models${NC}"
                if [ -n "$running_models" ]; then
                    log "${BLUE}Currently running models:${NC}"
                    echo "$running_models"
                fi
                return 0
            fi
        fi
        if ! pgrep -x "ollama" >/dev/null; then
            log "${YELLOW}Ollama process not found, starting ollama serve...${NC}"
            ollama serve >/dev/null 2>&1 &
            sleep 5
        fi
        log "${YELLOW}Waiting for Ollama API (attempt $i/30)...${NC}"
        sleep 2
    done
    log "${RED}Ollama API failed to respond after 60 seconds${NC}"
    return 1
}

# Update verify_model_installation function
verify_model_installation() {
    local model=$1
    log "${BLUE}Verifying model: $model${NC}"
    
    # Check if model exists in Ollama
    if ! ollama list | grep -q "^$model"; then
        log "${RED}Model $model not found in Ollama list${NC}"
        return 1
    fi
    
    # Check if model is already running and accessible
    if curl -s "http://localhost:11434/api/tags" | grep -q "\"name\":\"$model\""; then
        log "${GREEN}Model $model is already loaded and accessible${NC}"
        return 0
    fi
    
    # Try a simple API call to verify model access
    if curl -s -m 30 "http://localhost:11434/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model\",\"prompt\":\"test\",\"stream\":false}" >/dev/null; then
        log "${GREEN}Model $model is verified and accessible${NC}"
        return 0
    fi
    
    log "${RED}Model $model is not accessible${NC}"
    return 1
}

# Main installation process
install_docker
install_ollama

# Wait for Ollama to be ready
wait_for_ollama

# Pull required models
MODELS=("internlm2")  # Simplified model list for testing
for model in "${MODELS[@]}"; do
    if ! ollama list | grep -q "^$model"; then
        log "${BLUE}Pulling $model model...${NC}"
        if ! ollama pull $model; then
            log "${RED}Failed to pull $model model${NC}"
            continue
        fi
        # Wait for model to be registered after pulling
        sleep 5
    fi
    
    # Verify model installation
    if ! verify_model_installation "$model"; then
        log "${RED}Model $model verification failed${NC}"
        continue
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