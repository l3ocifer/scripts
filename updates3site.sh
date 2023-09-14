#!/bin/bash

# Use the current directory as the default site path
SITE_PATH=$(pwd)

# Extract the name of the current directory to use as the default bucket name
DEFAULT_BUCKET_NAME=$(basename "$SITE_PATH")

# Check if the default bucket exists
if ! aws s3 ls "s3://$DEFAULT_BUCKET_NAME" &> /dev/null; then
    echo "Bucket with the name $DEFAULT_BUCKET_NAME does not exist."
    read -p "Do you want to create it (y/n)? " decision

    if [[ $decision == "y" || $decision == "Y" ]]; then
        aws s3 mb "s3://$DEFAULT_BUCKET_NAME"
        if [ $? -ne 0 ]; then
            echo "Failed to create the bucket."
            exit 1
        fi
        BUCKET=$DEFAULT_BUCKET_NAME
    else
        read -p "Please specify the name of an existing S3 bucket: " BUCKET
    fi
else
    BUCKET=$DEFAULT_BUCKET_NAME
fi

# Build the site
npm run build
if [ $? -ne 0 ]; then
    echo "The update has failed. Could not build the site."
    exit 1
fi

# Sync the build directory with the S3 bucket
aws s3 sync build/ "s3://$BUCKET"
if [ $? -ne 0 ]; then
    echo "The update has failed. Could not sync files with S3."
    exit 1
fi

echo "The update is successful."
exit 0
