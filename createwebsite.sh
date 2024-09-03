#!/bin/bash
set -euo pipefail

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Disable the AWS CLI pager
export AWS_PAGER=""

# Disable Next.js telemetry
export NEXT_TELEMETRY_DISABLED=1

# Check for required commands
for cmd in git curl aws; do
    if ! command_exists $cmd; then
        echo "Error: $cmd is not installed. Please install it and try again." >&2
        exit 1
    fi
done

# Check if environment variables are set
if [ -z "${GITHUB_USERNAME:-}" ] || [ -z "${GITHUB_ACCESS_TOKEN:-}" ]; then
    echo "Error: GITHUB_USERNAME and GITHUB_ACCESS_TOKEN must be set in your environment." >&2
    exit 1
fi

# Function to get or set the last used domain
get_or_set_last_domain() {
    local config_file="$HOME/.createwebsite_config"
    if [ -f "$config_file" ]; then
        last_domain=$(cat "$config_file")
        read -p "Enter domain name (default: $last_domain): " DOMAIN_NAME
        DOMAIN_NAME=${DOMAIN_NAME:-$last_domain}
    else
        read -p "Enter domain name: " DOMAIN_NAME
    fi
    echo "$DOMAIN_NAME" > "$config_file"
}

setup_or_update_repo() {
    local default_repo="https://github.com/$GITHUB_USERNAME/website.git"
    local target_repo="https://$GITHUB_ACCESS_TOKEN@github.com/$GITHUB_USERNAME/$REPO_NAME.git"

    if [ -d "$REPO_PATH" ]; then
        echo "Repository already exists. Updating..."
        cd "$REPO_PATH"
        git fetch origin
        git reset --hard origin/master
    else
        echo "Cloning website template repository..."
        git clone "$default_repo" "$REPO_PATH"
        cd "$REPO_PATH"
        git remote rename origin default
    fi

    # Ensure we have the latest changes from the default repo
    git fetch default
    git checkout -B master default/master

    # Make scripts executable
    chmod +x scripts/*.sh

    # Set up the new origin
    git remote remove origin 2>/dev/null || true
    git remote add origin "$target_repo"

    # Update domain-specific files
    echo "$DOMAIN_NAME" > .domain
    sed -i.bak "s/DOMAIN_NAME_PLACEHOLDER/$DOMAIN_NAME/g" terraform/backend.tf
    rm -f terraform/backend.tf.bak

    # Commit and push changes
    git add .
    git commit -m "Update setup for $DOMAIN_NAME" || true
    echo "Pushing changes to GitHub..."
    if ! git push -u origin master --force; then
        echo "Failed to push to GitHub. Creating the repository..."
        curl -H "Authorization: token $GITHUB_ACCESS_TOKEN" \
             -d '{"name":"'"$REPO_NAME"'", "private": true}' \
             "https://api.github.com/user/repos"
        sleep 5  # Give GitHub a moment to create the repo
        git push -u origin master --force
    fi
}

# Main execution
if [ "${1:-}" == "--help" ]; then
    echo "Usage: $0 [td]"
    echo "  td: Destroy the infrastructure after setup"
    exit 0
fi

get_or_set_last_domain
REPO_NAME="paskaie.com"
REPO_PATH="$HOME/git/$REPO_NAME"

setup_or_update_repo

# Run the main setup script
if [ -f "scripts/main.sh" ]; then
    if [ "${1:-}" = "td" ]; then
        ./scripts/main.sh td
    else
        ./scripts.main.sh
    fi
else
    echo "Error: main.sh not found in the scripts directory." >&2
    exit 1
fi


echo "Website setup complete. Your repository is at https://github.com/$GITHUB_USERNAME/$REPO_NAME"
echo "Your website should be accessible at https://$DOMAIN_NAME once DNS propagation is complete."
