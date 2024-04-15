#!/bin/bash

# Assuming handle_error function and DOMAIN_NAME are defined in the main script or sourced globally.

# Check if the hosted zone already exists
EXISTING_HOSTED_ZONE=$(aws route53 list-hosted-zones | jq -r '.HostedZones[] | select(.Name=="'$DOMAIN_NAME'.") | .Id')

if [ -z "$EXISTING_HOSTED_ZONE" ]; then
  # Setup a public hosted zone
  HOSTED_ZONE_ID=$(aws route53 create-hosted-zone --name $DOMAIN_NAME --caller-reference $(date +%s) | jq -r '.HostedZone.Id') || handle_error "Failed to create hosted zone"
else
  echo "Hosted zone for $DOMAIN_NAME already exists with ID $EXISTING_HOSTED_ZONE"
  HOSTED_ZONE_ID=$EXISTING_HOSTED_ZONE
fi

# Export the hosted zone ID for use in other scripts
export HOSTED_ZONE_ID 
