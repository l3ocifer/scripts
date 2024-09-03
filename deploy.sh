#!/bin/bash

set -e

# Check if user has sudo privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "This script requires sudo privileges. Please run as root or with sudo. Exiting."
  exit 1
fi

c# Function to check if a command exists and is successful
command_exists_and_successful() {
  command -v "$1" &> /dev/null && "$1" --version &> /dev/null
}

# Function to determine the operating system
detect_os() {
  if grep -q Microsoft /proc/version; then
    echo "WSL"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macOS"
  elif grep -q Ubuntu /etc/os-release; then
    echo "Ubuntu"
  elif grep -q 'Amazon Linux' /etc/os-release; then
    echo "AmazonLinux"
  else
    echo "Unknown"
  fi
}

OS=$(detect_os)

# Check for package manager and install necessary tools
if [[ "$OS" == "Ubuntu" || "$OS" == "WSL" ]]; then
  if command_exists_and_successful apt-get; then
    # Install tools for Debian-based systems (Ubuntu/WSL)
    sudo apt-get update
    sudo apt-get install -y curl git unzip jq docker docker-compose
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm awscliv2.zip
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    echo "apt-get not found on a Debian-based system. Exiting."
    exit 1
  fi
elif [[ "$OS" == "AmazonLinux" ]]; then
  if command_exists_and_successful yum; then
    # Install tools for RedHat-based systems (Amazon Linux)
    sudo yum update -y
    sudo yum install -y curl git unzip jq
    sudo amazon-linux-extras install docker
    sudo service docker start
    sudo usermod -a -G docker ec2-user
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm awscliv2.zip
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    echo "yum not found on a RedHat-based system. Exiting."
    exit 1
  fi
elif [[ "$OS" == "macOS" ]]; then
  if command_exists_and_successful brew; then
    # Install tools for macOS using Homebrew
    brew install curl git unzip jq kubectl helm docker docker-compose
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
    sudo installer -pkg AWSCLIV2.pkg -target /
    rm AWSCLIV2.pkg
  else
    echo "Homebrew not found on macOS. Please install it first. Exiting."
    exit 1
  fi
else
  echo "Unsupported operating system or package manager. Exiting."
  exit 1
fi

# Function to check if a specific AWS profile exists
profile_exists() {
  aws configure list --profile "$1" &> /dev/null
}

if profile_exists default; then
  echo "Using AWS credentials from the default profile."
  # Additional check to ensure AWS credentials are valid
  aws sts get-caller-identity &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Invalid AWS credentials in the default profile. Exiting."
    exit 1
  fi
else

# Check for AWS credentials in environment variables
elif [[ -n ${AWS_ACCESS_KEY_ID} && -n ${AWS_SECRET_ACCESS_KEY} ]]; then
  echo "Using AWS credentials from environment variables."

# Prompt the user for input if neither profile nor environment variables are found
else
  read -p "Enter your AWS access key: " AWS_ACCESS_KEY_ID
  read -p "Enter your AWS secret access key: " AWS_SECRET_ACCESS_KEY

  # Configure AWS CLI with the provided input
  aws configure set aws_access_key_id ${AWS_ACCESS_KEY_ID}
  aws configure set aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}
fi

# Directory containing Terraform files
STATE_DIR="tfstate"
ROOT_DIR=$(pwd)  # Store the root directory path

# Check if directory exists
if [[ -d "$STATE_DIR" ]]; then
    cd "$STATE_DIR"

    # Check if directory has been initialized
    if [[ -d ".terraform" ]]; then
        echo "Terraform has been initialized."

        # Check if state file exists to determine if 'terraform apply' has been run
        if [[ -f "terraform.tfstate" ]]; then
            echo "Terraform has been applied."
        else
            echo "Terraform has not been applied. Applying now..."
            terraform apply -auto-approve

            # Get the bucket name after applying Terraform
            BUCKET_NAME=$(terraform output -raw s3_bucket_name)

            # Determine the operating system to adjust the sed command
            if [[ "$OSTYPE" == "darwin"* ]]; then
              # macOS
              SED_INPLACE="sed -i ''"
            else
              # Linux/WSL
              SED_INPLACE="sed -i"
            fi

            # Check if the bucket name in providers.tf is already set to the current version
            if ! grep -q "bucket\s*=\s*\"${BUCKET_NAME}\"" ../terraform/providers.tf; then
              # Update bucket name in providers.tf
              $SED_INPLACE "s/ea-eks-cubejs-tf-state/${BUCKET_NAME}/g" ../terraform/providers.tf
            fi
        fi
    else
        echo "Terraform has not been initialized. Initializing and applying now..."
        terraform init
        terraform apply -auto-approve
    fi

    # Change back to the root directory
    cd "$ROOT_DIR"
else
    echo "Directory $STATE_DIR does not exist."
fi

# Directory containing Terraform configurations
TF_DIR="terraform"

# Check if terraform directory exists
if [[ -d "$TF_DIR" ]]; then
    cd "$TF_DIR"

    # Check if directory has been initialized
    if [[ -d ".terraform" ]]; then
        echo "Terraform in $TF_DIR has been initialized."

        # Check if state file exists to determine if 'terraform apply' has been run
        if [[ -f "terraform.tfstate" ]]; then
            echo "Terraform in $TF_DIR has been applied."
        else
            echo "Terraform in $TF_DIR has not been applied. Applying now..."
            terraform apply -auto-approve
        fi
    else
        echo "Terraform in $TF_DIR has not been initialized. Initializing and applying now..."
        terraform init
        terraform apply -auto-approve
    fi

    # Change back to the root directory
    cd "$ROOT_DIR"
else
    echo "Directory $TF_DIR does not exist."
fi

# Update Kubeconfig
AWS_REGION=$(aws configure get region)
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

# Get the LoadBalancer URL
LOAD_BALANCER_URL=$(kubectl get svc cube-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get the Hosted Zone ID for your domain
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name dataeng.edanalytics.org --max-items 1 --query 'HostedZones[0].Id' --output text)

# Create the Route53 record
aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch '{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "<dns-name for url>",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "'$LOAD_BALANCER_URL'"
          }
        ]
      }
    }
  ]
}'

# Write the LoadBalancer URL to output
echo "Visit the following URL to test the deployment: http://${LOAD_BALANCER_URL}"

echo "The site can sometimes take another minute or two to load. Please check the browser again in 1 minute if no message appears."
