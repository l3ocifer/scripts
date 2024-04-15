#!/bin/bash

# Assuming handle_error function and REPO_PATH are defined in the main script or sourced globally.

# Move back to repo root
cd $REPO_PATH || handle_error "Failed to change directory to the repo directory"

# Check for existing output.tf file in the current directory
if [ ! -f "./output.tf" ]; then
    # Create an output.tf file in the current directory
    cat << EOF > ./output.tf
output "cloudfront_dist_id" {
  value = module.static_site.cloudfront_dist_id
}
output "s3_bucket_name" {
  value = module.static_site.site_bucket_name
}
EOF
    if [ $? -ne 0 ]; then
        handle_error "Failed to create output.tf"
    fi
else
    echo "output.tf already exists. Skipping creation."
fi
