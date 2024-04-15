#!/bin/bash
set -e
set -u

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Function to clean up temporary files
cleanup() {
    echo "Cleaning up temporary files..."
    rm -f awscliv2.zip terraform.zip
}

# Set the repository path
REPO_PATH=${1:-$(pwd)}

# Check for awscli
if ! command -v aws &> /dev/null
then
    echo "awscli could not be found. Installing..."
    curl "https://d1vvhvl2y92vvt.cloudfront.net/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install || handle_error "Failed to install awscli"
fi

# Check for create-react-app
if ! command -v npx &> /dev/null
then
    echo "npx could not be found. Installing..."
    npm install -g npx || handle_error "Failed to install npx"
fi

# Check for Terraform
if ! command -v terraform &> /dev/null
then
    echo "Terraform could not be found. Installing..."
    curl "https://releases.hashicorp.com/terraform/1.0.5/terraform_1.0.5_linux_amd64.zip" -o "terraform.zip"
    unzip terraform.zip
    sudo mv terraform /usr/local/bin/ || handle_error "Failed to install Terraform"
fi

# Check for AWS credentials
if [ -z "$AWS_PROFILE" ] && [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_SECRET_ACCESS_KEY" ]
then
    echo "AWS credentials not found. Please enter them now."
    read -p 'AWS Access Key ID: ' AWS_ACCESS_KEY_ID
    read -sp 'AWS Secret Access Key: ' AWS_SECRET_ACCESS_KEY
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
fi

# Clean up temporary files
cleanup
