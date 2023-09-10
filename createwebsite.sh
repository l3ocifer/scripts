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

# Check for domain name
DOMAIN_NAME=${DOMAIN_NAME:-}
if [ -z "$DOMAIN_NAME" ]
then
    echo "Domain name not found. Please enter it now."
    read -p 'Domain Name: ' DOMAIN_NAME
    export DOMAIN_NAME=$DOMAIN_NAME
fi

# Create a punctuation-free version of the domain name
DOMAINNAME=${DOMAIN_NAME//[^a-zA-Z0-9]/}

# Set header name to domain name without extension
HEADER_NAME=${DOMAIN_NAME%.*}

# Check if the hosted zone already exists
EXISTING_HOSTED_ZONE=$(aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'$DOMAIN_NAME'.") | .Id')

if [ -z "$EXISTING_HOSTED_ZONE" ]; then
  # Setup a public hosted zone
  HOSTED_ZONE_ID=$(aws route53 create-hosted-zone --name $DOMAIN_NAME --caller-reference $(date +%s) | jq -r '.HostedZone.Id') || handle_error "Failed to create hosted zone"
else
  echo "Hosted zone for $DOMAIN_NAME already exists with ID $EXISTING_HOSTED_ZONE"
  HOSTED_ZONE_ID=$EXISTING_HOSTED_ZONE
fi

# Check if React app already exists
if [ -d "$REPO_PATH/$DOMAINNAME" ]; then
    echo "React app already exists. Skipping creation and moving to build."
else
    # Prompt for background and text colors
    echo "Choose a color scheme:"
    echo "1. Dark Blue (#00008B) and Bright Pink (#FF69B4)"
    echo "2. Light Green (#90EE90) and Orange (#FFA500)"
    echo "3. Teal (#008080) and Reddish-Orange (#FF4500)"
    echo "4. Pastel Pink (#FFD1DC) and Pastel Blue (#B0E0E6)"
    echo "5. Deep Purple (#800080) and Gold (#FFD700)"
    echo "6. Bright Red (#FF0000) and Pale Yellow (#FFFFE0)"
    echo "7. Dark Grey (#A9A9A9) and Bright Yellow (#FFFF00)"
    echo "8. Custom colors."
    read -p 'Choice (default: 8): ' COLOR_CHOICE
    COLOR_CHOICE=${COLOR_CHOICE:-8}

    case $COLOR_CHOICE in
        1)
            BACKGROUND_COLOR="#00008B"
            TEXT_COLOR="#FF69B4"
            ;;
        2)
            BACKGROUND_COLOR="#90EE90"
            TEXT_COLOR="#FFA500"
            ;;
        3)
            BACKGROUND_COLOR="#008080"
            TEXT_COLOR="#FF4500"
            ;;
        4)
            BACKGROUND_COLOR="#FFD1DC"
            TEXT_COLOR="#B0E0E6"
            ;;
        5)
            BACKGROUND_COLOR="#800080"
            TEXT_COLOR="#FFD700"
            ;;
        6)
            BACKGROUND_COLOR="#FF0000"
            TEXT_COLOR="#FFFFE0"
            ;;
        7)
            BACKGROUND_COLOR="#A9A9A9"
            TEXT_COLOR="#FFFF00"
            ;;
        8)
            read -p 'Background Color (default: #000000): ' BACKGROUND_COLOR
            BACKGROUND_COLOR=${BACKGROUND_COLOR:-#000000}
            read -p 'Text Color (default: #FFFFFF): ' TEXT_COLOR
            TEXT_COLOR=${TEXT_COLOR:-#FFFFFF}
            ;;
    esac

    # Create a React app
    npx create-react-app $REPO_PATH/$DOMAINNAME || handle_error "Failed to create a React app"
fi

# Check for images in the repository
IMAGES=$(find $REPO_PATH -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" -o -name "*.gif" -o -name "*.svg")

# Check for a content file in the repository
if [ ! -f "$REPO_PATH/content-$DOMAINNAME.txt" ]
then
    echo "Content file not found. Please enter the content now."
    echo "Enter 'skip' to skip a section."
    read -p 'Title of Org: ' TITLE_OF_ORG
    read -p 'Mission Statement: ' MISSION_STATEMENT
    read -p 'About Org: ' ABOUT_ORG
    read -p 'Contact Info: ' CONTACT_INFO
    while true
    do
        read -p 'Section Title (or "skip"): ' SECTION_TITLE
        if [ "$SECTION_TITLE" == "skip" ]
        then
            break
        fi
        read -p 'Section Content: ' SECTION_CONTENT
        echo -e "$SECTION_TITLE\n$SECTION_CONTENT" >> $REPO_PATH/content-$DOMAINNAME.txt
    done
fi

# Create a CSS module for App component
echo ".App {" > $REPO_PATH/$DOMAINNAME/src/App.module.css
echo "  text-align: center;" >> $REPO_PATH/$DOMAINNAME/src/App.module.css
echo "  margin: 0 auto;" >> $REPO_PATH/$DOMAINNAME/src/App.module.css
echo "  max-width: 800px;" >> $REPO_PATH/$DOMAINNAME/src/App.module.css
echo "  padding: 20px;" >> $REPO_PATH/$DOMAINNAME/src/App.module.css
echo "}" >> $REPO_PATH/$DOMAINNAME/src/App.module.css

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i "" "s/<title>$DOMAIN_NAME<\/title>/<title>$HEADER_NAME<\/title>/" $REPO_PATH/$DOMAINNAME/public/index.html
else
    # Linux and others
    sed -i "s/<title>$DOMAIN_NAME<\/title>/<title>$HEADER_NAME<\/title>/" $REPO_PATH/$DOMAINNAME/public/index.html
fi


# Insert the content into the React app
echo "import React from 'react';" > $REPO_PATH/$DOMAINNAME/src/App.js
echo "import styles from './App.module.css';" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "const content = [" >> $REPO_PATH/$DOMAINNAME/src/App.js
while IFS= read -r line
do
    echo "  \`$line\`," >> $REPO_PATH/$DOMAINNAME/src/App.js
done < $REPO_PATH/content-$DOMAINNAME.txt
echo "];" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "function App() {" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "  return (" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "    <div className={styles.App}>" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "      {content.map((paragraph, index) => (" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "        <p key={index}>{paragraph}</p>" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "      ))}" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "    </div>" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "  );" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "}" >> $REPO_PATH/$DOMAINNAME/src/App.js
echo "export default App;" >> $REPO_PATH/$DOMAINNAME/src/App.js

# Insert the images into the React app
for image in $IMAGES
do
    # Check if the image has already been moved
    if [ ! -f "$REPO_PATH/$DOMAINNAME/src/$(basename $image)" ]; then
        mv $image $REPO_PATH/$DOMAINNAME/src/ || handle_error "Failed to move the image: $image"
    else
        echo "Image $(basename $image) has already been moved. Skipping..."
    fi
done


# Build the React app
cd $REPO_PATH/$DOMAINNAME
npm run build || handle_error "Failed to build the React app"

# Move back to repo root
cd $REPO_PATH || handle_error "Failed to change directory to the repo directory"

# Check if backend repo already exists
if [ -d "$REPO_PATH/tf-s3-backend-$DOMAINNAME" ]; then
    echo "Backend repo already exists. Skipping clone and Terraform run."

    # Change directory to existing backend repo
    cd tf-s3-backend-$DOMAINNAME || handle_error "Failed to change directory to the tf-backend directory"

    # Get the output values from Terraform
    BUCKET_NAME=$(terraform output -raw s3_bucket_name) || handle_error "Failed to get the bucket name from Terraform"
    DYNAMODB_TABLE_NAME=$(terraform output -raw dynamodb_table_name) || handle_error "Failed to get the DynamoDB table name from Terraform"
else
    # Clone backend repo
    git clone https://github.com/l3ocifer/tf-s3-backend.git tf-s3-backend-$DOMAINNAME
    cd tf-s3-backend-$DOMAINNAME || handle_error "Failed to change directory to the tf-backend directory"

    # Run Terraform
    terraform init || handle_error "Failed to initialize Terraform"
    terraform apply -auto-approve || handle_error "Failed to apply Terraform configuration"

    # Get the output values from Terraform
    BUCKET_NAME=$(terraform output -raw s3_bucket_name) || handle_error "Failed to get the bucket name from Terraform"
    DYNAMODB_TABLE_NAME=$(terraform output -raw dynamodb_table_name) || handle_error "Failed to get the DynamoDB table name from Terraform"
fi

# Move back to repo root
cd $REPO_PATH || handle_error "Failed to change directory to the repo directory"

# Clone landingpage repo
if [ ! -d "landingpage-$DOMAINNAME" ]; then
    git clone https://github.com/l3ocifer/landingpage.git landingpage-$DOMAINNAME
fi

cd landingpage-$DOMAINNAME || handle_error "Failed to change directory to the Terraform directory"

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

# Check for existing main.tf file in the current directory
if [ ! -f "./main.tf" ]
then
    # Create a main.tf file in the current directory
    cat << EOF > ./main.tf
provider "aws" {
  region = "us-east-1"
}

module "static_website" {
  source      = "./terraform"
  domain_name = "$DOMAIN_NAME"
}
EOF
    if [ $? -ne 0 ]
    then
        handle_error "Failed to create main.tf"
    fi
else
    echo "main.tf already exists. Skipping creation."
fi

# Run Terraform
terraform init || handle_error "Failed to initialize Terraform"
terraform apply -auto-approve || handle_error "Failed to apply Terraform configuration"

# set S3 bucket
S3_BUCKET_ROOT=$(terraform output s3_root_id | tr -d \")

# set CloudFront distribution ID
CF_DISTRIBUTION_ID=$(terraform output cf_distribution_id | tr -d \")

# remove files from S3
aws s3 rm "s3://${S3_BUCKET_ROOT}" --recursive

# sync files with S3
aws s3 sync $REPO_PATH/$DOMAINNAME/build "s3://${S3_BUCKET_ROOT}" || handle_error "Failed to sync the React app with the S3 bucket"

# invalidate CloudFront cache
export AWS_PAGER=""
aws cloudfront create-invalidation --distribution-id "${CF_DISTRIBUTION_ID}" --paths "/*" || handle_error "Failed to invalidate the cloudfront distribution"

# move back to repo root
cd $REPO_PATH
# Initialize a new git repository in the directory from which the script is run, only if it hasn't been initialized already
if [ ! -d ".git" ]; then
    git init

    # Add a .gitignore suitable for React and Terraform
    cat << EOF > .gitignore
    # React
    $DOMAINNAME/node_modules/
    $DOMAINNAME/build/
    *.log

    # Terraform
    **/.terraform/
    *.tfstate
    *.tfstate.backup
    *.tfvars

    # Misc
    *.DS_Store
EOF

    # Make an initial commit
    git add .
    git commit -m "Initial commit"

    # Create a new GitHub repository (You need to set GITHUB_TOKEN as an environment variable)
    REPO_NAME="website-$DOMAINNAME"
    curl -H "Authorization: token $GITHUB_ACCESS_TOKEN" --data '{"name":"'$REPO_NAME'"}' https://api.github.com/user/repos

    # Link to remote and push
    git remote add origin "https://github.com/l3ocifer/$REPO_NAME.git"
    git branch -M main
    git push -u origin main
fi


echo "process complete."
