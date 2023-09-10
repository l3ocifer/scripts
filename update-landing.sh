#!/bin/bash

# Check if environment variables are set. If not, prompt the user to enter them
if [ -z "$FRONTPAGE_PATH" ]
then
  read -p "Enter the path to your React app: " FRONTPAGE_PATH
fi

if [ -z "$FRONTPAGE_BUCKET" ]
then
  read -p "Enter the name of your S3 bucket: " FRONTPAGE_BUCKET
fi

if [ -z "$FRONTPAGE_DISTRIBUTION" ]
then
  read -p "Enter the ID of your CloudFront distribution: " FRONTPAGE_DISTRIBUTION
fi

if [ -z "$FRONTPAGE_URL" ]
then
  read -p "Enter the URL of your frontpage: " FRONTPAGE_URL
fi

# Navigate to the React app's directory and build the app
cd "$FRONTPAGE_PATH" && npm run build
if [ $? -ne 0 ]
then
  echo "The update has failed. Could not build the React app."
  exit 1
fi

# Sync the build directory with the S3 bucket
aws s3 sync build/ s3://"$FRONTPAGE_BUCKET"
if [ $? -ne 0 ]
then
  echo "The update has failed. Could not sync files with S3."
  exit 1
fi

# Invalidate the CloudFront cache
aws cloudfront create-invalidation --distribution-id "$FRONTPAGE_DISTRIBUTION" --paths "/*"
if [ $? -ne 0 ]
then
  echo "The update has failed. Could not invalidate the CloudFront cache."
  exit 1
fi

echo "The update is successful."
exit 0
