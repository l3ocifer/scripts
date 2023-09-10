#!/bin/bash

# Disable AWS CLI pager
export AWS_PAGER=""

# Try to fetch the current profile from the environment variable
CURRENT_AWS_PROFILE=${AWS_PROFILE:-""}

# If AWS_PROFILE environment variable isn't set, try to get it from the aws CLI configuration
if [[ -z "$CURRENT_AWS_PROFILE" ]]; then
    CURRENT_AWS_PROFILE=$(aws configure get profile 2>/dev/null || echo "")
fi

# Prompt the user for the AWS profile, using the detected profile as the default
read -p "Enter the AWS profile (default: $CURRENT_AWS_PROFILE): " PROFILE_INPUT
AWS_PROFILE=${PROFILE_INPUT:-$CURRENT_AWS_PROFILE}

# If the user didn't use the default AWS_PROFILE, attempt to switch and test the profile
if [[ "$AWS_PROFILE" != "$CURRENT_AWS_PROFILE" ]]; then
    echo "Attempting to switch to profile: $AWS_PROFILE"

    # Test the profile by trying a basic AWS CLI command
    aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1

    # If the command fails, we assume the profile is not active
    if [[ $? -ne 0 ]]; then
        echo "Profile $AWS_PROFILE is not active."

        # logic for setting up aws sso profile automagically goes here - I only have macos working to date, and it requires manual intervention at one point;P
        # For this example, this kind of works for macos
        # Open Chrome with the 'Leo(Work)' profile
        #open -a "Google Chrome" --args "--profile-directory='Profile 17'"

        # Switch back to iTerm2
        #osascript -e 'tell application "iTerm" to activate'

        # Use expect to configure AWS SSO
        #expect -c '
        #    spawn aws configure sso --profile eaedfi
        #    expect "SSO session name (Recommended):" { send "\r\r" }
        #    expect "SSO start URL \\\[https://edanalytics.awsapps.com/start#\\\]:" { send "\r\r" }
        #    expect "SSO region \\\[us-east-2\\\]" { send "\r\r" }
        #    expect "There are 2 AWS accounts available to you." { send "\r\r" }
        #    expect "CLI default client Region \\\[us-east-1\\\]:" { send "\r\r" }
        #    expect "CLI default output format \\\[None\\\]:" { send "\r\r" }
        #    interact
        #'

        # Set AWS_PROFILE and AWS_REGION environment variables
        #export AWS_PROFILE=eaedfi
        #export AWS_REGION=us-east-1

        # The above section is commented out for now. Uncomment it when you're ready to use it.

        echo "Please manually set the correct AWS profile before proceeding."
        exit 1
    else
        echo "Successfully switched to profile: $AWS_PROFILE"
        export AWS_PROFILE
    fi
fi

# Get the default region from the current AWS profile
DEFAULT_REGION=$(aws configure get region --profile $AWS_PROFILE 2>/dev/null)

# If no default region is found, exit the script
if [ -z "$DEFAULT_REGION" ]; then
    echo "No AWS region is set in the profile. Please set a region before running the script."
    exit 1
fi

# Prompt the user for the AWS region, using the current profile's region as the default
read -p "Enter the AWS region for the S3 bucket (default: $DEFAULT_REGION): " AWS_REGION_INPUT
AWS_REGION=${AWS_REGION_INPUT:-$DEFAULT_REGION}

# Get the current directory
CURRENT_DIR=$(pwd)

# Prompt the user for the directory to navigate to, using the current directory as the default
read -p "Enter the directory path for the git repository (default: $CURRENT_DIR): " DIRECTORY_INPUT
TARGET_DIRECTORY=${DIRECTORY_INPUT:-$CURRENT_DIR}

# Navigate to the specified or default directory
cd "$TARGET_DIRECTORY"

# Check the current git branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)

# If BRANCH_NAME is already set in the environment, use it. Otherwise, use the current branch.
BRANCH_NAME=${BRANCH_NAME:-$CURRENT_BRANCH}

# Ask the user to confirm if the current branch is the desired branch
read -p "Do you want to use the current branch ($BRANCH_NAME) [Y/n]? " use_current
use_current=${use_current:-Y}

# If the user doesn't want to use the current branch, prompt for the desired branch
if [[ $use_current != [Yy] ]]; then
    read -p "Enter the name of the branch [main]: " branch_input
    BRANCH_NAME=${branch_input:-main}
    export BRANCH_NAME
fi

# Fetch the latest changes and checkout the specified branch
git fetch origin
git checkout $BRANCH_NAME
git pull origin $BRANCH_NAME

# List the current S3 buckets
echo "Current S3 buckets:"
aws s3 ls

# Prompt the user for the S3 bucket name with the default being the branch name
read -p "Enter the name for the S3 bucket (default: $BRANCH_NAME): " bucket_input
BUCKET_NAME=${bucket_input:-$BRANCH_NAME}

# Attempt to create the S3 bucket
echo "Checking or creating S3 bucket named $BUCKET_NAME..."
output=$(aws s3api create-bucket --bucket "$BUCKET_NAME" --region $AWS_REGION 2>&1)
result=$?

# Check if the bucket creation failed because the bucket already exists
if [ $result -ne 0 ]; then
    if [[ $output == *'BucketAlreadyExists'* ]]; then
        echo "Bucket already exists. Proceeding..."
    else
        echo "Error: Failed to create bucket."
        echo "$output"
        exit 1
    fi
fi

# Sync repo content with the S3 bucket excluding .git directory and deleting any extra files in the bucket
aws s3 sync . s3://$BUCKET_NAME/ --exclude ".git/*" --delete

echo "Updated the S3 bucket ($BUCKET_NAME) with the latest content from branch: $BRANCH_NAME."
