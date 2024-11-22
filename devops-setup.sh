#!/bin/bash

# Complete DevOps Environment Setup Script
# Supports: macOS, Ubuntu/Debian, WSL
# Last updated: 2024-11-14
# Version: 2.0.1

# Disable exit on error to allow the script to continue even if some commands fail
set +euo pipefail
IFS=$'\n\t'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initialize error collection
declare -a FAILED_INSTALLATIONS=()

# Logging functions
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }

# Check success of commands
check_success() {
    if [ $? -eq 0 ]; then
        log "✓ $1 completed successfully"
    else
        error "✗ Error during $1"
        FAILED_INSTALLATIONS+=("$1")
    fi
}

# Detect OS
detect_os() {
    if [ "$(uname)" == "Darwin" ]; then
        echo "macos"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    else
        echo "ubuntu"
    fi
}

OS_TYPE=$(detect_os)
log "Detected OS: $OS_TYPE"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
log "Working directory: $TEMP_DIR"

# Install basic dependencies based on OS
install_basic_dependencies() {
    log "Installing basic dependencies..."
    case $OS_TYPE in
        "macos")
            if ! command_exists brew; then
                log "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                check_success "Homebrew installation"
                export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
            fi
            brew update
            brew install \
                git \
                curl \
                wget \
                jq \
                yq \
                zsh \
                gnupg \
                coreutils \
                gnu-getopt \
                openjdk \
                python3 \
                thefuck \
                starship \
                zoxide \
                bun \
                unzip \
                zip
            ;;
        "ubuntu"|"wsl")
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y \
                git \
                curl \
                wget \
                jq \
                yq \
                zsh \
                unzip \
                zip \
                apt-transport-https \
                ca-certificates \
                gnupg \
                lsb-release \
                software-properties-common \
                python3 \
                python3-pip
            ;;
    esac
    check_success "Basic dependencies installation"
}

# Install Oh My Zsh and plugins
install_shell_environment() {
    if [ "$OS_TYPE" == "macos" ]; then
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            log "Installing Oh My Zsh..."
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

            log "Installing Zsh plugins..."
            git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
            git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
            check_success "Oh My Zsh and plugins installation"
        fi
    fi
}

# Install Docker and Docker Compose
install_docker() {
    if ! command_exists docker; then
        log "Installing Docker..."
        case $OS_TYPE in
            "macos")
                brew install --cask docker
                ;;
            "ubuntu"|"wsl")
                curl -fsSL https://get.docker.com -o get-docker.sh
                sudo sh get-docker.sh
                sudo usermod -aG docker "$USER"
                ;;
        esac
        check_success "Docker installation"
    fi

    if ! command_exists docker-compose; then
        log "Installing Docker Compose..."
        case $OS_TYPE in
            "macos")
                brew install docker-compose
                ;;
            "ubuntu"|"wsl")
                sudo apt-get install -y docker-compose-plugin
                ;;
        esac
        check_success "Docker Compose installation"
    fi
}

# Install Node Version Manager (nvm)
install_nvm() {
    if [ ! -d "$HOME/.nvm" ]; then
        log "Installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
        check_success "NVM installation"
    fi
}

# Install AWS CLI v2
install_aws_cli() {
    if ! command_exists aws; then
        log "Installing AWS CLI v2..."
        case $OS_TYPE in
            "macos")
                curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
                sudo installer -pkg AWSCLIV2.pkg -target /
                rm AWSCLIV2.pkg
                ;;
            "ubuntu"|"wsl")
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                unzip -q awscliv2.zip
                sudo ./aws/install --update
                rm -rf aws awscliv2.zip
                ;;
        esac
        check_success "AWS CLI installation"
    fi
}

# Install Terraform
install_terraform() {
    if ! command_exists terraform; then
        log "Installing Terraform..."
        case $OS_TYPE in
            "macos")
                brew tap hashicorp/tap
                brew install hashicorp/tap/terraform
                ;;
            "ubuntu"|"wsl")
                wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                sudo apt-get update
                sudo apt-get install -y terraform
                ;;
        esac
        check_success "Terraform installation"
    fi
}

# Install Kubernetes tools
install_kubernetes_tools() {
    log "Installing Kubernetes tools..."

    # Install kubectl
    if ! command_exists kubectl; then
        log "Installing kubectl..."
        case $OS_TYPE in
            "macos")
                brew install kubectl
                ;;
            "ubuntu"|"wsl")
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                rm kubectl
                ;;
        esac
        check_success "kubectl installation"
    fi

    # Install Krew
    if ! command_exists kubectl-krew; then
        log "Installing Krew..."
        (
            set -x; cd "$(mktemp -d)" &&
            OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
            ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/armv.*/arm/' -e 's/aarch64$/arm64/')" &&
            KREW="krew-${OS}_${ARCH}" &&
            curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
            tar zxvf "${KREW}.tar.gz" &&
            ./"${KREW}" install krew
        )
        export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
        if [ "$OS_TYPE" == "macos" ]; then
            echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> "$HOME/.zshrc"
        else
            echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        check_success "Krew installation"
    fi

    # Install Krew plugins
    log "Installing Krew plugins..."
    kubectl krew install neat
    kubectl krew index add kvaps https://github.com/kvaps/krew-index
    kubectl krew install kvaps/node-shell
    check_success "Krew plugins installation"

    # Install eksctl
    if ! command_exists eksctl; then
        log "Installing eksctl..."
        case $OS_TYPE in
            "macos")
                brew tap weaveworks/tap
                brew install weaveworks/tap/eksctl
                ;;
            "ubuntu"|"wsl")
                curl --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
                sudo mv /tmp/eksctl /usr/local/bin
                ;;
        esac
        check_success "eksctl installation"
    fi

    # Install Kind
    if ! command_exists kind; then
        log "Installing Kind..."
        case $OS_TYPE in
            "macos")
                brew install kind
                ;;
            "ubuntu"|"wsl")
                curl -Lo ./kind "https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64"
                sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
                rm kind
                ;;
        esac
        check_success "Kind installation"
    fi

    # Install Helm
    if ! command_exists helm; then
        log "Installing Helm..."
        case $OS_TYPE in
            "macos")
                brew install helm
                ;;
            "ubuntu"|"wsl")
                curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
                sudo apt-get install apt-transport-https --yes
                echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
                sudo apt-get update
                sudo apt-get install -y helm
                ;;
        esac
        check_success "Helm installation"
    fi

    # Install Velero
    if ! command_exists velero; then
        log "Installing Velero..."
        VELERO_VERSION=$(curl -s https://api.github.com/repos/vmware-tanzu/velero/releases/latest | grep tag_name | cut -d '"' -f 4)
        case $OS_TYPE in
            "macos")
                curl -fsSL "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-darwin-amd64.tar.gz" -o velero.tar.gz
                ;;
            "ubuntu"|"wsl")
                curl -fsSL "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz" -o velero.tar.gz
                ;;
        esac
        tar -xzf velero.tar.gz
        sudo mv velero-*/velero /usr/local/bin/
        rm -rf velero*
        check_success "Velero installation"
    fi

    # Install k9s
    if ! command_exists k9s; then
        log "Installing k9s..."
        K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f 4)
        case $OS_TYPE in
            "macos")
                curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Darwin_amd64.tar.gz" -o k9s.tar.gz
                ;;
            "ubuntu"|"wsl")
                curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -o k9s.tar.gz
                ;;
        esac
        tar xzf k9s.tar.gz
        sudo install -o root -g root -m 0755 k9s /usr/local/bin/k9s
        rm -rf k9s*
        check_success "k9s installation"
    fi

    # Install kubectx and kubens
    if ! command_exists kubectx; then
        log "Installing kubectx and kubens..."
        case $OS_TYPE in
            "macos")
                brew install kubectx
                ;;
            "ubuntu"|"wsl")
                sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
                sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
                sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens
                ;;
        esac
        check_success "kubectx and kubens installation"
    fi
}

# Install Go
install_golang() {
    if ! command_exists go; then
        log "Installing Go..."
        case $OS_TYPE in
            "macos")
                brew install go
                ;;
            "ubuntu"|"wsl")
                GO_VERSION=$(curl -s https://go.dev/VERSION?m=text)
                wget "https://golang.org/dl/${GO_VERSION}.linux-amd64.tar.gz"
                sudo tar -C /usr/local -xzf "${GO_VERSION}.linux-amd64.tar.gz"
                rm "${GO_VERSION}.linux-amd64.tar.gz"
                ;;
        esac
        check_success "Go installation"
    fi
}

# Install Python tools
install_python_tools() {
    log "Installing Python tools..."
    case $OS_TYPE in
        "macos")
            brew install python3
            ;;
        "ubuntu"|"wsl")
            sudo apt-get install -y python3 python3-pip
            ;;
    esac

    # Install Miniconda
    if [ ! -d "$HOME/miniconda" ]; then
        log "Installing Miniconda..."
        case $OS_TYPE in
            "macos")
                wget https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O miniconda.sh
                ;;
            "ubuntu"|"wsl")
                wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
                ;;
        esac
        bash miniconda.sh -b -p $HOME/miniconda
        rm miniconda.sh
        check_success "Miniconda installation"
    fi
}

# Install additional tools
install_additional_tools() {
    log "Installing additional tools..."
    case $OS_TYPE in
        "macos")
            brew install \
                thefuck \
                starship \
                zoxide \
                atuin \
                bun \
                aichat \
                ollama \
                jan \
                m-cli
            ;;
        "ubuntu"|"wsl")
            # TheFuck
            pip3 install --user thefuck

            # Starship
            curl -sS https://starship.rs/install.sh | sh -s -- -y

            # Zoxide
            curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash

            # Atuin
            bash <(curl https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh)

            # Bun
            curl -fsSL https://bun.sh/install | bash

            # Install aichat
            pip3 install --user aichat

            # Install Ollama and Jan
            # Ollama is macOS only, so we skip it on Linux
            # Install Sherlock
            pip3 install --user sherlock
            ;;
    esac
    check_success "Additional tools installation"
}

# Configure shell
setup_shell_config() {
    log "Setting up shell configuration..."

    if [ "$OS_TYPE" == "macos" ]; then
        SHELL_RC="$HOME/.zshrc"
        SHELL_NAME="zsh"
    else
        SHELL_RC="$HOME/.bashrc"
        SHELL_NAME="bash"
    fi

    # Create shell configuration
    cat > "$SHELL_RC" << EOL
# If you come from bash you might have to change your \$PATH.
# export PATH=\$HOME/bin:/usr/local/bin:\$PATH

# Path to your oh-my-zsh installation.
export ZSH="\$HOME/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="robbyrussell"

# Plugins
plugins=(
    git
    nvm
    zsh-autosuggestions
    zsh-syntax-highlighting
    docker
    kubectl
    terraform
    aws
)

# Load Oh My Zsh
if [ -f "\$ZSH/oh-my-zsh.sh" ]; then
    source \$ZSH/oh-my-zsh.sh
fi

# User configuration

# Aliases
alias t=terraform
alias k=kubectl
alias d=docker
alias dc='docker compose'
alias g=git
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kge='kubectl get events --sort-by=.metadata.creationTimestamp'
alias aws-who='aws sts get-caller-identity'
alias aws-ls='aws configure list-profiles'
alias gs='git status'
alias o='ollama run llama3'
alias chat='aichat'
alias reload='source ~/$SHELL_RC'

# AWS Profile Aliases
alias leo="export AWS_PROFILE=aws-l3o-iam-leo && export AWS_REGION=us-east-1"
alias dre="export AWS_PROFILE=aws-dre-iam-leo && export AWS_REGION=us-east-1"
alias pie="export AWS_PROFILE=aws-pie-iam-leo && export AWS_REGION=us-east-1"
alias scy="export AWS_PROFILE=aws-scryar-iam-leo && export AWS_REGION=us-west-2"
alias awr="export AWS_PROFILE=aws-awr-iam-leo && export AWS_REGION=us-east-1"
alias stein="export AWS_PROFILE=aws-stein-iam-L3o && export AWS_REGION=us-east-1"

# Scripts Aliases
alias domain='~/.scripts/google-domain-aws-route53.sh'
alias newrepo='~/.scripts/create-repo.sh'
alias fork='~/.scripts/fork-repo.sh'
alias aoe='~/.scripts/editzshrc.sh'
alias pubkey='~/.scripts/pubkeyfinder.sh'
alias user='~/.scripts/createadmin.sh'
alias ups3='~/.scripts/updates3site.sh'
alias commit='~/.scripts/gitcommit.sh'
alias update='~/.scripts/pullrepos.sh'
alias wordpress='~/.scripts/updatewordpress.sh'
alias agb='~/.scripts/addgitbranch.sh'
alias sha='~/.scripts/showsshsha.sh'
alias copy='~/.scripts/copytoclipboard.sh'
alias newkey='~/.scripts/createsshkey.sh'
alias ghu='~/git/githired/scripts/update.sh'
alias repotxt='~/.scripts/.python-scripts/repo-to-txt.py'
alias updatemaster='current_branch=\$(git rev-parse --abbrev-ref HEAD) && git checkout master && git merge \$current_branch && git push origin master && git checkout \$current_branch'
alias testssh='~/.scripts/test-ssh.sh'

# Path Updates
export PATH="\$HOME/.local/bin:\$PATH"
export PATH="\$PATH:/usr/local/go/bin"
export GOPATH="\$HOME/go"
export PATH="\$PATH:\$GOPATH/bin"
export JAVA_HOME=\$(/usr/libexec/java_home 2>/dev/null || echo "/usr/lib/jvm/java-11-openjdk-amd64")
export PATH="\$HOME/.bun/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
export KREW_ROOT="\$HOME/.krew"
export PATH="\${KREW_ROOT:-\$HOME/.krew}/bin:\$PATH"

# NVM setup
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"

# Conda setup
if [ -f "\$HOME/miniconda/etc/profile.d/conda.sh" ]; then
    . "\$HOME/miniconda/etc/profile.d/conda.sh"
else
    export PATH="\$HOME/miniconda/bin:\$PATH"
fi

# Initialize tools
eval "\$(starship init $SHELL_NAME)"
eval "\$(zoxide init $SHELL_NAME)"
eval "\$(atuin init $SHELL_NAME)"
eval "\$(thefuck --alias)"

# SSH Agent Setup
eval \$(ssh-agent -s)
ssh-add ~/.ssh/leo-personal
ssh-add ~/.ssh/leo-github

# Bun completions
[ -s "\$HOME/.bun/_bun" ] && source "\$HOME/.bun/_bun"

# Atuin environment
. "\$HOME/.atuin/env"

# Aliases for kubectl
alias kgpa="kubectl get pods -A"
alias kgda="kubectl get deploy -A"
alias kgsa="kubectl get secrets -A"
alias kgsvc="kubectl get service -A"

# Set history timestamp format
export HISTTIMEFORMAT="%d/%m/%y %T "

# Git configuration
export GITHUB_USERNAME='l3ocifer'
export GITHUB_EMAIL='lpask001@gmail.com'

EOL

    check_success "Shell configuration"
}

# Main installation
main() {
    log "Starting DevOps environment setup..."

    install_basic_dependencies
    install_shell_environment
    install_docker
    install_nvm
    install_aws_cli
    install_terraform
    install_kubernetes_tools
    install_golang
    install_python_tools
    install_additional_tools
    setup_shell_config

    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"

    log "Installation complete! Please:"
    log "1. Log out and back in for all changes to take effect"
    log "2. Configure your AWS credentials using 'aws configure'"
    log "3. Set up any additional SSH keys needed for your repositories"
    log "4. Configure Git with your email and name using 'git config'"

    # Report failed installations
    if [ ${#FAILED_INSTALLATIONS[@]} -ne 0 ]; then
        error "The following installations failed:"
        for item in "${FAILED_INSTALLATIONS[@]}"; do
            error "- $item"
        done
    else
        log "All installations completed successfully!"
    fi
}

main
