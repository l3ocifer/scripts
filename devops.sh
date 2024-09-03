#!/bin/bash

# Function to check if a package is installed
is_installed() {
  dpkg -l "$1" &> /dev/null
  return $?
}

# Update and upgrade packages
echo "Updating and upgrading system packages..."
sudo apt update && sudo apt upgrade -y || echo "Failed to update and upgrade. Continuing..."

# Install common utilities
for pkg in unzip zip jq git curl wget; do
  if ! is_installed "$pkg"; then
    echo "Installing $pkg..."
    sudo apt install -y "$pkg" || echo "Failed to install $pkg. Continuing..."
  else
    echo "$pkg is already installed."
  fi
done

# Docker installation
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh ./get-docker.sh || echo "Failed to install Docker. Continuing..."
  rm get-docker.sh
else
  echo "Docker is already installed."
fi

# Docker Compose installation
if ! command -v docker-compose &> /dev/null; then
  echo "Installing Docker Compose..."
  sudo apt install -y docker-compose || echo "Failed to install Docker Compose. Continuing..."
else
  echo "Docker Compose is already installed."
fi

# AWS CLI v2 installation
if ! command -v aws &> /dev/null; then
  echo "Installing AWS CLI v2..."
  curl -sLo "awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  unzip awscliv2.zip
  sudo ./aws/install || echo "Failed to install AWS CLI v2. Continuing..."
  rm -rf awscliv2.zip aws
else
  echo "AWS CLI v2 is already installed."
fi

# kubectl installation
if ! command -v kubectl &> /dev/null; then
  echo "Installing kubectl..."
  curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl || echo "Failed to install kubectl. Continuing..."
else
  echo "kubectl is already installed."
fi

# Krew installation
if ! kubectl krew &> /dev/null; then
  echo "Installing krew..."
  (
    set -x; cd "$(mktemp -d)" &&
    OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
    ARCH="$(uname -m)" &&
    KREW="krew-${OS}_${ARCH}" &&
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
    tar zxvf "${KREW}.tar.gz" &&
    ./"${KREW}" install krew
  ) || echo "Failed to install krew. Continuing..."
  echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >>~/.bashrc
  source ~/.bashrc
else
  echo "krew is already installed."
fi

# Terraform installation
if ! command -v terraform &> /dev/null; then
  echo "Installing Terraform..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update && sudo apt-get install -y terraform || echo "Failed to install Terraform. Continuing..."
else
  echo "Terraform is already installed."
fi

# Cleanup
echo "Cleaning up..."
sudo apt autoremove -y || echo "Failed to clean up. Continuing..."

echo "DevOps environment setup complete. Some steps may have failed; check the output above."

