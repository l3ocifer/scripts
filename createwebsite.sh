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
# Create websites directory if it doesn't exist
mkdir -p "$HOME/git/websites"
REPO_PATH="$HOME/git/websites/$REPO_NAME"

setup_or_update_repo() {
    local default_repo="https://github.com/$GITHUB_USERNAME/aws-s3-cdn-acm-website.git"
    local target_repo="https://$GITHUB_ACCESS_TOKEN@github.com/$GITHUB_USERNAME/$REPO_NAME.git"

    if [ -d "$REPO_PATH" ]; then
        echo "Repository already exists. Updating..."
        cd "$REPO_PATH"
        
        # Check if origin remote exists and fetch if it does
        if git remote get-url origin &>/dev/null; then
            git fetch origin 2>/dev/null || true
            git reset --hard origin/master 2>/dev/null || git reset --hard origin/main 2>/dev/null || true
        fi
        
        # Ensure default remote exists for template updates
        if ! git remote get-url default &>/dev/null; then
            git remote add default "$default_repo" 2>/dev/null || true
        fi
    else
        echo "Cloning website template repository..."
        git clone "$default_repo" "$REPO_PATH"
        cd "$REPO_PATH"
        git remote rename origin default
    fi

    # Ensure we have the latest changes from the default repo
    git fetch default 2>/dev/null || true
    git checkout -B master default/master 2>/dev/null || git checkout -B main default/main 2>/dev/null || true

    # Make scripts executable
    if [ -d "scripts" ]; then
        chmod +x scripts/*.sh 2>/dev/null || true
    fi

    # Update domain-specific files
    echo "$DOMAIN_NAME" > .domain
    if [ -f "terraform/backend.tf" ]; then
        sed -i.bak "s/REPO_NAME_PLACEHOLDER/$REPO_NAME/g" terraform/backend.tf
        rm -f terraform/backend.tf.bak
    fi
    if [ -d "terraform" ]; then
        cp .domain terraform/ 2>/dev/null || true
    fi

    # Create or get hosted zone ID (if setup script exists)
    # Note: AWS setup is typically handled by Python scripts in main.sh
    if [ -f "./scripts/setup_aws.sh" ]; then
        source ./scripts/setup_aws.sh
        create_or_get_hosted_zone
    elif [ -f "./scripts/setup_aws.py" ]; then
        echo "Note: AWS setup will be handled by Python scripts in main.sh"
    else
        echo "Note: AWS setup will be handled by main.sh script"
    fi

    # Ensure .hosted_zone_id is in the repo root (if it exists)
    if [ -f .hosted_zone_id ]; then
        cp .hosted_zone_id "$REPO_PATH/" 2>/dev/null || true
    else
        echo "Note: .hosted_zone_id will be created by main.sh if needed"
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
    git remote add origin "$target_repo" 2>/dev/null || {
        echo "Warning: Could not add origin remote. It may already exist."
        git remote set-url origin "$target_repo" 2>/dev/null || true
    }

    # Determine current branch name
    current_branch=$(git branch --show-current 2>/dev/null || echo "master")
    
    # Push changes
    echo "Pushing changes to GitHub..."
    git push -u origin "$current_branch" --force 2>/dev/null || {
        echo "Warning: Push failed. Attempting to push to master/main..."
        git push -u origin master --force 2>/dev/null || git push -u origin main --force 2>/dev/null || true
    }
}

setup_or_update_repo

# Run the main setup script
# The template uses Python scripts (scripts/main.py), not shell scripts
# Ensure we're in the repo directory
if [ -d "$REPO_PATH" ]; then
    cd "$REPO_PATH"
else
    echo "Error: Repository path $REPO_PATH does not exist." >&2
    exit 1
fi

# Set environment variables for Python scripts
export DOMAIN_NAME="$DOMAIN_NAME"
export REPO_NAME="$REPO_NAME"
# Handle PYTHONPATH safely (may be unset)
if [ -z "${PYTHONPATH:-}" ]; then
    export PYTHONPATH="$REPO_PATH/scripts"
else
    export PYTHONPATH="$REPO_PATH/scripts:$PYTHONPATH"
fi

if [ -f "scripts/main.py" ]; then
    echo "Running scripts/main.py..."
    
    # Create a virtual environment for this project (similar to create-website.py)
    VENV_PATH="$REPO_PATH/.venv"
    CLEANUP_VENV=1
    
    # Cleanup function for venv
    cleanup_venv() {
        if [ "$CLEANUP_VENV" -eq 1 ] && [ -d "$VENV_PATH" ]; then
            echo "Cleaning up virtual environment..."
            rm -rf "$VENV_PATH"
        fi
    }
    
    # Set up trap to cleanup on exit (including failures)
    trap cleanup_venv EXIT INT TERM
    
    # Create venv if it doesn't exist
    if [ ! -d "$VENV_PATH" ]; then
        echo "Creating virtual environment..."
        python3 -m venv "$VENV_PATH" || {
            echo "Error: Failed to create virtual environment." >&2
            exit 1
        }
    fi
    
    # Activate the virtual environment
    source "$VENV_PATH/bin/activate" || {
        echo "Error: Failed to activate virtual environment." >&2
        exit 1
    }
    
    # Install dependencies in the venv
    echo "Installing Python dependencies in virtual environment..."
    pip install --upgrade pip --quiet || {
        echo "Warning: Failed to upgrade pip, continuing anyway..."
    }
    pip install boto3 botocore requests python-dotenv || {
        echo "Error: Failed to install Python dependencies." >&2
        exit 1
    }
    
    # Verify installation
    if ! python -c "import boto3" 2>/dev/null; then
        echo "Error: Dependencies installed but boto3 still not importable." >&2
        exit 1
    fi
    
    # Run the main script
    python -m scripts.main
    EXIT_CODE=$?
    
    # If we get here successfully, don't cleanup the venv (keep it for future use)
    if [ $EXIT_CODE -eq 0 ]; then
        CLEANUP_VENV=0
        trap - EXIT INT TERM
        echo "Virtual environment preserved at $VENV_PATH for future use"
    else
        exit $EXIT_CODE
    fi
elif [ -f "create-website.py" ]; then
    echo "Running create-website.py..."
    python3 create-website.py
elif [ -f "scripts/main.sh" ]; then
    ./scripts/main.sh
else
    echo "Error: No main setup script found (scripts/main.py, create-website.py, or scripts/main.sh)." >&2
    echo "Available files in scripts directory:" >&2
    ls -la scripts/ >&2 || true
    exit 1
fi

echo "Website setup complete. Your repository is at https://github.com/$GITHUB_USERNAME/$REPO_NAME"
echo "Your website should be accessible at https://$DOMAIN_NAME once DNS propagation is complete."
