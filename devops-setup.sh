#!/bin/bash

# DevOps Tools Installation Script
# This script installs and configures common DevOps tools on Ubuntu/Debian
# Last updated: 2024-11-13

set -euo pipefail
IFS=$'\n\t'

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        log "✓ $1 completed successfully"
    else
        log "✗ Error during $1"
        exit 1
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create temporary directory for downloads
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
log "Working directory: $TEMP_DIR"

# Update system packages
log "Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y
check_success "System update"

# Install basic utilities
log "Installing basic utilities..."
sudo apt-get install -y \
    git \
    zip \
    unzip \
    jq \
    curl \
    wget \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common
check_success "Basic utilities installation"

# Install Docker
if ! command_exists docker; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker "$USER"
    check_success "Docker installation"
fi

# Install Docker Compose V2
if ! command_exists docker-compose; then
    log "Installing Docker Compose..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
    check_success "Docker Compose installation"
fi

# Install AWS CLI v2
if ! command_exists aws; then
    log "Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install --update
    check_success "AWS CLI installation"
fi

# Install AWS IAM Authenticator
if ! command_exists aws-iam-authenticator; then
    log "Installing AWS IAM Authenticator..."
    curl -fsSL "https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/latest/download/aws-iam-authenticator_0.6.11_linux_amd64" -o aws-iam-authenticator
    sudo install -o root -g root -m 0755 aws-iam-authenticator /usr/local/bin/aws-iam-authenticator
    check_success "AWS IAM Authenticator installation"
fi

# Install kubectl
if ! command_exists kubectl; then
    log "Installing kubectl..."
    curl -fsSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    echo 'alias k=kubectl' >>~/.bashrc
    check_success "kubectl installation"
fi

# Install Krew
if ! command_exists kubectl-krew; then
    log "Installing Krew..."
    OS="$(uname | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')"
    KREW="krew-${OS}_${ARCH}"
    curl -fsSL "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" -o "${KREW}.tar.gz"
    tar zxf "${KREW}.tar.gz"
    ./"${KREW}" install krew
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
    echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >>~/.bashrc
    check_success "Krew installation"

    # Install Krew plugins
    kubectl krew install neat
    kubectl krew index add kvaps https://github.com/kvaps/krew-index
    kubectl krew install kvaps/node-shell
    check_success "Krew plugins installation"
fi

# Install eksctl
if ! command_exists eksctl; then
    log "Installing eksctl..."
    curl -fsSL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" -o eksctl.tar.gz
    tar xzf eksctl.tar.gz
    sudo install -o root -g root -m 0755 eksctl /usr/local/bin/eksctl
    check_success "eksctl installation"
fi

# Install KinD
if ! command_exists kind; then
    log "Installing KinD..."
    curl -fsSL "https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64" -o kind
    sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
    check_success "KinD installation"
fi

# Install Helm
if ! command_exists helm; then
    log "Installing Helm..."
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install -y helm
    check_success "Helm installation"
fi

# Install Velero
if ! command_exists velero; then
    log "Installing Velero..."
    VELERO_VERSION=$(curl -s https://api.github.com/repos/vmware-tanzu/velero/releases/latest | grep tag_name | cut -d '"' -f 4)
    curl -fsSL "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz" -o velero.tar.gz
    tar -xzf velero.tar.gz
    sudo mv velero-*/velero /usr/local/bin/
    check_success "Velero installation"
fi

# Install Terraform
if ! command_exists terraform; then
    log "Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update
    sudo apt-get install -y terraform
    check_success "Terraform installation"
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"
log "Cleaned up temporary files"

# Final verification
log "Verifying installations..."
docker --version
docker compose version
aws --version
aws-iam-authenticator version
kubectl version --client
eksctl version
kind version
helm version
velero version --client-only
terraform version

log "Installation complete! Please log out and back in for all changes to take effect."
