#!/bin/bash

# Check if AWS CLI and jq are installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI could not be found. Please install it to proceed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install it to proceed."
    exit 1
fi

# Check or prompt for DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
  read -p "Please enter your Google registered domain name (e.g., example.com): " DOMAIN_NAME
fi

# Check if the hosted zone exists and create if it doesn't
check_and_create_hosted_zone() {
  HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output json | jq -r '.[0]')
  if [ "$HOSTED_ZONE_ID" == "null" ]; then
    HOSTED_ZONE_ID=$(aws route53 create-hosted-zone --name "${DOMAIN_NAME}" --caller-reference "$(date +%s)" --query 'HostedZone.Id' --output text)
    echo "Created a new hosted zone with ID: $HOSTED_ZONE_ID"
  fi
}

# Main Script Logic
check_and_create_hosted_zone

# Fetch Route 53 nameservers for the hosted zone
ROUTE53_NS=$(aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --query "ResourceRecordSets[?Type=='NS' && Name=='${DOMAIN_NAME}.'].ResourceRecords[].Value" --output json | jq -r '.[]')

# Prompt user to update Google Domains with Route 53 Nameservers
echo "IMPORTANT: To manage your domain with AWS Route 53, please update the nameservers in your Google Domains account to:"
for ns in $ROUTE53_NS; do
  echo "  - $ns"
done
