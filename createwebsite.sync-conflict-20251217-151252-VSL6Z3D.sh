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

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "Error: AWS CLI is not configured. Please run 'aws configure' and try again." >&2
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

get_or_set_last_domain
echo "$DOMAIN_NAME" > .domain
REPO_NAME=$(echo "$DOMAIN_NAME" | sed -E 's/\.[^.]+$//')
REPO_PATH="$HOME/git/$REPO_NAME"

setup_or_update_repo() {
    local default_repo="https://github.com/$GITHUB_USERNAME/website.git"
    local target_repo="https://$GITHUB_ACCESS_TOKEN@github.com/$GITHUB_USERNAME/$REPO_NAME.git"

    if [ -d "$REPO_PATH" ]; then
        echo "Repository already exists. Updating..."
        cd "$REPO_PATH"
        git fetch origin
        git reset --hard origin/master || git reset --hard origin/main
    else
        echo "Cloning website template repository..."
        git clone "$default_repo" "$REPO_PATH"
        cd "$REPO_PATH"
        git remote rename origin default
    fi

    # Ensure we have the latest changes from the default repo
    git fetch default
    git checkout -B master default/master || git checkout -B main default/main

    # Make scripts executable
    chmod +x scripts/*.sh

    # Update domain-specific files
    echo "$DOMAIN_NAME" > .domain
    sed -i.bak "s/REPO_NAME_PLACEHOLDER/$REPO_NAME/g" terraform/backend.tf
    rm -f terraform/backend.tf.bak
    cp .domain terraform/

    # Create or get hosted zone ID
    source ./scripts/setup_aws.sh
    create_or_get_hosted_zone

    # Ensure .hosted_zone_id is in the repo root
    if [ -f .hosted_zone_id ]; then
        cp .hosted_zone_id "$REPO_PATH/" 2>/dev/null || true
    else
        echo "Warning: .hosted_zone_id file not found after create_or_get_hosted_zone"
    fi

    # Commit changes
    git add .
    git commit -m "Update setup for $DOMAIN_NAME" || true

    # Create the repository if it doesn't exist
    echo "Creating or updating GitHub repository..."
    curl -H "Authorization: token $GITHUB_ACCESS_TOKEN" \
         -d '{"name":"'"$REPO_NAME"'", "private": true}' \
         "https://api.github.com/user/repos" || true

    # Set up the new origin
    git remote remove origin 2>/dev/null || true
    git remote add origin "$target_repo"

    # Push changes
    echo "Pushing changes to GitHub..."
    git push -u origin master --force || git push -u origin main --force
}

setup_or_update_repo

# Run the main setup script
if [ -f "scripts/main.sh" ]; then
    ./scripts/main.sh
else
    echo "Error: main.sh not found in the scripts directory." >&2
    exit 1
fi

echo "Website setup complete. Your repository is at https://github.com/$GITHUB_USERNAME/$REPO_NAME"
echo "Your website should be accessible at https://$DOMAIN_NAME once DNS propagation is complete."
