#!/bin/bash

# Define the RDS endpoint
RDS_ENDPOINT=${RDS_ENDPOINT:-"lp-dev-53-cqrs-databasestack-auroradbfirstinstance-dzrlfrvlfzfh.cvicgflaxfsm.us-east-1.rds.amazonaws.com"}

# Define the Bastion ID
BASTION_ID=${BASTION_ID:-"i-0f4416377cba0a704"}

# Generate a random port for the bastion host
BASTION_PORT=$(jot -r 1 9000 10000)

# Function to restore iptables and cleanup on exit
cleanup() {
  echo "Restoring iptables and cleaning up..."

  # Restore the iptables rules from the backup
  aws ssm send-command \
    --instance-ids $BASTION_ID \
    --document-name "AWS-RunShellScript" \
    --parameters commands=["sudo iptables-restore < /tmp/iptables_backup"]

  # Clean up the backup on the bastion host
  aws ssm send-command \
    --instance-ids $BASTION_ID \
    --document-name "AWS-RunShellScript" \
    --parameters commands=["sudo rm /tmp/iptables_backup"]
}

# Register the cleanup function to run on script exit
trap cleanup EXIT INT TERM HUP

echo "Backing up current iptables rules on the bastion host..."

# Backup the current iptables rules on the bastion host
if ! aws ssm send-command \
  --instance-ids $BASTION_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands=["sudo iptables-save > /tmp/iptables_backup"]
then
    echo "Error backing up iptables. Exiting."
    exit 1
fi

echo "Setting up iptables rules for port forwarding..."

# Set up the iptables rules for port forwarding
if ! aws ssm send-command \
  --instance-ids $BASTION_ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands=["sudo iptables -t nat -A PREROUTING -p tcp --dport $BASTION_PORT -j DNAT --to-destination $RDS_ENDPOINT:5432"]
then
    echo "Error setting up iptables rules. Exiting."
    exit 1
fi

echo "Starting the SSM port forwarding session..."

# Start the SSM port forwarding session
aws ssm start-session --target $BASTION_ID \
  --document-name "AWS-StartPortForwardingSession" \
  --parameters "localPortNumber=5432,portNumber=$BASTION_PORT"
