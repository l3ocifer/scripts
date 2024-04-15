#!/bin/bash

# Assuming handle_error function, REPO_PATH, BUCKET_NAME, and DYNAMODB_TABLE_NAME are defined in the main script or sourced globally.

# Move back to repo root
cd $REPO_PATH || handle_error "Failed to change directory to the repo directory"

# Check if providers.tf already exists
if [ ! -f providers.tf ]; then
  # Create the providers.tf file with the bucket and DynamoDB table names
  cat << EOF > providers.tf
terraform {
  backend "s3" {
    bucket = "$BUCKET_NAME"
    key    = "global/s3/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "$DYNAMODB_TABLE_NAME"
    encrypt        = true
  }
}
EOF
else
  echo "providers.tf already exists. Skipping creation."
fi
