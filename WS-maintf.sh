#!/bin/bash

# Assuming handle_error function, REPO_PATH, DOMAIN_NAME, and ZONE_ID are defined in the main script or sourced globally.

# Move back to repo root
cd $REPO_PATH || handle_error "Failed to change directory to the repo directory"

# Check for existing main.tf file in the current directory
if [ ! -f "./main.tf" ]; then
    # Create a main.tf file in the current directory using the custom Terraform module
    cat << EOF > ./main.tf
terraform {
  required_version = ">= 1.0.2"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 5.15.0"
      configuration_aliases = [aws.us-east-1]
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "static_site" {
  source = "./path/to/your/custom/module" # Replace with the actual path to your module

  domain_name   = "$DOMAIN_NAME"

  # Customize other variables as needed based on your module's input variables
  # ...
}
EOF
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create main.tf"
        exit 1
    else
        # Initialize and run Terraform if main.tf was created
        terraform init || { echo "Error: Failed to initialize Terraform"; exit 1; }
        terraform apply -auto-approve || { echo "Error: Failed to apply Terraform configuration"; exit 1; }
    fi
else
    echo "main.tf already exists. Skipping creation."
fi
