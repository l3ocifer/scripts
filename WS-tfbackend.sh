#!/bin/bash

# Assuming handle_error function and REPO_PATH are defined in the main script or sourced globally.

# Check if backend repo already exists
if [ -d "$REPO_PATH/tf-s3-backend-$DOMAINNAME" ]; then
    echo "Backend repo already exists. Skipping clone and Terraform run."
else
    # Clone backend repo
    git clone https://github.com/l3ocifer/tf-s3-backend.git tf-s3-backend-$DOMAINNAME
    cd tf-s3-backend-$DOMAINNAME || handle_error "Failed to change directory to the tf-backend directory"

    # Run Terraform
    terraform init || handle_error "Failed to initialize Terraform"
    terraform apply -auto-approve || handle_error "Failed to apply Terraform configuration"
fi

# Change directory to backend repo if not already in it
[ "$(basename "$PWD")" != "tf-s3-backend-$DOMAINNAME" ] && cd tf-s3-backend-$DOMAINNAME

# Get the output values from Terraform
BUCKET_NAME=$(terraform output -raw s3_bucket_name) || handle_error "Failed to get the bucket name from Terraform"
DYNAMODB_TABLE_NAME=$(terraform output -raw dynamodb_table_name) || handle_error "Failed to get the DynamoDB table name from Terraform"

# Export these values for use in the main script or other modules
export BUCKET_NAME
export DYNAMODB_TABLE_NAME

# Move back to repo root
cd $REPO_PATH || handle_error "Failed to change directory to the repo directory" 
