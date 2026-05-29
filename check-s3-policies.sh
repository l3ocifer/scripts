#!/bin/bash

# AWS S3 Policy Permission Checker
# Identifies customer managed policies with potentially risky S3 permissions

set -e

# Check AWS CLI installation
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check jq installation
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install it first."
    exit 1
fi

# Create output directory
mkdir -p policy-reports

# Set timestamp format
TIMESTAMP=$(date +"%Y%m%d-%H%M")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Analyzing AWS Account: $ACCOUNT_ID"
echo "Checking for customer managed policies with s3:GetObject and s3:PutObject permissions..."

# Get all customer managed policies
policies=$(aws iam list-policies --scope Local --query 'Policies[*].[PolicyName,Arn,DefaultVersionId]' --output json)

# Create report file
REPORT_FILE="policy-reports/s3-policy-report-$TIMESTAMP.txt"
echo "AWS S3 Policy Analysis Report" > "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "Account ID: $ACCOUNT_ID" >> "$REPORT_FILE"
echo "----------------------------------------" >> "$REPORT_FILE"

# Function to check if policy has both permissions
check_policy_permissions() {
    local policy_arn=$1
    local version_id=$2
    local policy_name=$3
    
    # Get policy version details
    policy_doc=$(aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$version_id" --query 'PolicyVersion.Document' --output json)
    
    # Check for both permissions
    if echo "$policy_doc" | jq -e '.Statement[] | select((.Effect == "Allow") and (.Action | if type == "string" then . else .[] end) | strings | test("s3:GetObject|s3:PutObject"))' > /dev/null; then
        echo "⚠️  Found potentially risky policy: $policy_name" | tee -a "$REPORT_FILE"
        echo "   ARN: $policy_arn" >> "$REPORT_FILE"
        echo "   Version: $version_id" >> "$REPORT_FILE"
        echo "   Policy Document:" >> "$REPORT_FILE"
        echo "$policy_doc" | jq '.' >> "$REPORT_FILE"
        echo "----------------------------------------" >> "$REPORT_FILE"
        return 0
    fi
    return 1
}

# Process each policy
found_risky_policies=false
echo "$policies" | jq -c '.[]' | while read -r policy; do
    name=$(echo "$policy" | jq -r '.[0]')
    arn=$(echo "$policy" | jq -r '.[1]')
    version=$(echo "$policy" | jq -r '.[2]')
    
    if check_policy_permissions "$arn" "$version" "$name"; then
        found_risky_policies=true
    fi
done

if [ "$found_risky_policies" = false ]; then
    echo "✅ No customer managed policies found with potentially risky S3 permissions." | tee -a "$REPORT_FILE"
fi

echo "Report saved to: $REPORT_FILE" 