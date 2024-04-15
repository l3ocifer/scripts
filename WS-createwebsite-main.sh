#!/bin/bash
set -e
set -u

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Call requirements script
./requirements.sh

# Set the repository path
REPO_PATH=${1:-$(pwd)}

# Check for domain name
DOMAIN_NAME=${DOMAIN_NAME:-}
if [ -z "$DOMAIN_NAME" ]; then
    echo "Domain name not found. Please enter it now."
    read -p 'Domain Name: ' DOMAIN_NAME
    export DOMAIN_NAME=$DOMAIN_NAME
fi

# Create a punctuation-free version of the domain name
DOMAINNAME=${DOMAIN_NAME//[^a-zA-Z0-9]/}

# Set header name to domain name without extension
HEADER_NAME=${DOMAIN_NAME%.*}

# Check and create the hosted zone if needed
./WS-checkcreatehostedzone.sh

# Move back to repo root
cd $REPO_PATH || handle_error "Failed to change directory to the repo directory"

# Check and create providers.tf if needed
./WS-createproviderstf.sh

# Check and create output.tf if needed
./WS-createoutputtf.sh

# Fetch hosted zone ID for the provided domain name
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output text | cut -d'/' -f3)

# Check if we found the hosted zone ID
if [[ -z "${ZONE_ID}" ]]; then
    echo "Error: Unable to find a hosted zone for the domain: $DOMAIN_NAME"
    exit 1
fi

# Check and create main.tf if needed
./create-main.tf.sh

# Gather outputs for s3_bucket_name
S3_BUCKET_NAME_CHECK=$(terraform output -raw s3_bucket_name 2>&1 | tail -n 1)
if [[ $S3_BUCKET_NAME_CHECK == *"No outputs found"* ]]; then
    handle_error "Failed to retrieve the s3_bucket_name from Terraform outputs"
else
    S3_BUCKET_ROOT=$S3_BUCKET_NAME_CHECK
fi

# Gather outputs for cloudfront_dist_id
CF_DISTRIBUTION_ID_CHECK=$(terraform output -raw cloudfront_dist_id 2>&1 | tail -n 1)
if [[ $CF_DISTRIBUTION_ID_CHECK == *"No outputs found"* ]]; then
    handle_error "Failed to retrieve the cloudfront_dist_id from Terraform outputs"
else
    CF_DISTRIBUTION_ID=$CF_DISTRIBUTION_ID_CHECK
fi

# remove files from S3
aws s3 rm "s3://${S3_BUCKET_ROOT}" --recursive

# sync files with S3
aws s3 sync $REPO_PATH/$DOMAINNAME/build "s3://${S3_BUCKET_ROOT}" || handle_error "Failed to sync the React app with the S3 bucket"

# invalidate CloudFront cache
export AWS_PAGER=""
aws cloudfront create-invalidation --distribution-id "${CF_DISTRIBUTION_ID}" --paths "/*" || handle_error "Failed to invalidate the cloudfront distribution"

# move back to repo root
cd $REPO_PATH

# Initialize Git repository if needed
./webgitinit.sh

echo "process complete."
