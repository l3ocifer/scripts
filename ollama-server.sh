#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# Enable and ensure service is running
log "${BLUE}Ensuring Ollama service is enabled and running...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable ollama
if ! sudo systemctl is-active --quiet ollama; then
    sudo systemctl restart ollama
    sleep 5
fi

# Check service status
if sudo systemctl is-active --quiet ollama; then
    log "${GREEN}Ollama service is running successfully${NC}"
    log "${GREEN}API endpoint available at http://localhost:11434${NC}"
    log "${GREEN}Test the API with: curl http://localhost:11434/api/generate -d '{\"model\":\"llama3.2:3b\",\"prompt\":\"Why is the sky blue?\"}'${NC}"
    log "${GREEN}Or with Qwen: curl http://localhost:11434/api/generate -d '{\"model\":\"qwen2.5-coder:32b\",\"prompt\":\"Write a Python function to calculate Fibonacci numbers\"}'${NC}"
else
    log "${RED}Failed to start Ollama service. Check logs with: sudo journalctl -u ollama${NC}"
    exit 1
fi 
