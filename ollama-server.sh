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

# Check if Ollama is already installed
if command -v ollama >/dev/null 2>&1; then
    log "${GREEN}Ollama is already installed${NC}"
else
    log "${BLUE}Installing Ollama...${NC}"
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Check if service file exists
if [ -f /etc/systemd/system/ollama.service ]; then
    log "${GREEN}Ollama service file already exists${NC}"
else
    log "${BLUE}Creating systemd service...${NC}"
    sudo tee /etc/systemd/system/ollama.service > /dev/null << 'EOF'
[Unit]
Description=Ollama Service
After=network-online.target
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
StandardOutput=append:/var/log/ollama.log
StandardError=append:/var/log/ollama.error.log

[Install]
WantedBy=multi-user.target
EOF

    # Fix service file permissions
    sudo sed -i "s/\$USER/$USER/g" /etc/systemd/system/ollama.service
fi

# Ensure log files exist with correct permissions
for logfile in /var/log/ollama.log /var/log/ollama.error.log; do
    if [ ! -f "$logfile" ]; then
        sudo touch "$logfile"
        sudo chown $USER:$USER "$logfile"
    fi
done

# Ensure Ollama service is properly configured and running
log "${BLUE}Configuring Ollama service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable ollama

# Restart service if not running or if config changed
if ! sudo systemctl is-active --quiet ollama || [ -n "$SERVICE_UPDATED" ]; then
    log "${BLUE}Starting Ollama service...${NC}"
    sudo systemctl restart ollama
    # Wait for Ollama API to be fully ready
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/version >/dev/null; then
            break
        fi
        sleep 2
    done
fi

# Function to check if model exists
model_exists() {
    ollama list | grep -q "^$1\s"
    return $?
}

# Pull models if they don't exist
if ! model_exists "llama3.2:3b"; then
    log "${BLUE}Pulling Llama 3.2 3B model...${NC}"
    ollama pull llama3.2:3b
else
    log "${GREEN}Llama 3.2 3B model already exists${NC}"
fi

if ! model_exists "qwen2.5-coder:32b"; then
    log "${BLUE}Pulling Qwen 2.5 Coder 32B model...${NC}"
    ollama pull qwen2.5-coder:32b
else
    log "${GREEN}Qwen 2.5 Coder 32B model already exists${NC}"
fi

# Check if Docker is installed and running
if command -v docker >/dev/null 2>&1; then
    log "${GREEN}Docker is already installed${NC}"
    # Ensure Docker service is running
    if ! systemctl is-active --quiet docker; then
        log "${BLUE}Starting Docker service...${NC}"
        sudo systemctl start docker
        sleep 3
    fi
else
    log "${BLUE}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    sudo systemctl enable docker
    sudo systemctl start docker
    sleep 3
    log "${YELLOW}Please log out and back in for Docker permissions to take effect${NC}"
fi

# Function to run Open WebUI container
run_webui() {
    local desired_url="$1"
    local container_name="$2"
    
    # Check if container exists and is running correctly
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        CURRENT_URL=$(docker inspect "$container_name" | grep -o 'OLLAMA_API_BASE_URL=[^,]*' || echo '')
        if [[ "$CURRENT_URL" == *"$desired_url"* ]] && \
           curl -s "http://localhost:3000" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Remove existing container if it exists
    docker rm -f "$container_name" >/dev/null 2>&1
    
    # Wait for Ollama API to be accessible
    for i in {1..10}; do
        if curl -s "$desired_url/version" >/dev/null; then
            break
        fi
        sleep 2
    done

    # Only proceed if API is accessible
    if ! curl -s "$desired_url/version" >/dev/null; then
        log "${RED}Ollama API not accessible at $desired_url${NC}"
        return 1
    fi
    
    docker run -d \
        --name "$container_name" \
        --restart always \
        --add-host=host.docker.internal:host-gateway \
        -p 3000:8080 \
        -e OLLAMA_API_BASE_URL="http://host.docker.internal:11434/api" \
        -v open-webui:/app/backend/data \
        ghcr.io/open-webui/open-webui:main

    # Wait for container to be ready and verify API connection
    for i in {1..15}; do
        if docker logs "$container_name" 2>&1 | grep -q "Application startup complete" && \
           curl -s "http://localhost:3000" >/dev/null 2>&1; then
            # Verify API connection from inside container
            if docker exec "$container_name" curl -s http://host.docker.internal:11434/api/version >/dev/null; then
                return 0
            fi
        fi
        sleep 2
    done
    return 1
}

# Update container check section
if docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    log "${GREEN}Open WebUI container exists${NC}"
    CURRENT_URL=$(docker inspect open-webui | grep -o 'OLLAMA_API_BASE_URL=[^,]*' || echo '')
    DESIRED_URL="http://host.docker.internal:11434/api"
    
    if [[ "$CURRENT_URL" != *"$DESIRED_URL"* ]]; then
        log "${BLUE}Recreating container with updated configuration...${NC}"
        if run_webui "$DESIRED_URL" "open-webui"; then
            log "${GREEN}Successfully updated Open WebUI configuration${NC}"
        else
            log "${RED}Failed to create container. Check logs with: docker logs open-webui${NC}"
            exit 1
        fi
    fi
else
    log "${BLUE}Installing Open WebUI...${NC}"
    if ! run_webui "http://localhost:11434/api" "open-webui"; then
        log "${RED}Failed to create container. Check logs with: docker logs open-webui${NC}"
        exit 1
    fi
fi

# Check Open WebUI status and provide access instructions
if docker ps --format '{{.Names}}' | grep -q '^open-webui$'; then
    log "${GREEN}Open WebUI is running successfully${NC}"
    
    # Check if running in SSH session
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
        log "${GREEN}To access Open WebUI from your local machine, run:${NC}"
        log "${BLUE}ssh -L 3000:localhost:3000 -L 11434:localhost:11434 $(whoami)@$LOCAL_IP${NC}"
        log "${GREEN}Then open http://localhost:3000 in your browser${NC}"
    else
        log "${GREEN}Web interface available at http://localhost:3000${NC}"
    fi
else
    log "${RED}Failed to start Open WebUI container. Check logs with: docker logs open-webui${NC}"
fi 