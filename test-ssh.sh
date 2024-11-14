#!/bin/bash

# File to store failed connections
failed_connections="failed_connections.txt"

# Clear the failed connections file if it exists
> "$failed_connections"

# Function to test SSH connection
test_ssh_connection() {
    local host="$1"
    if ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$host" exit >/dev/null 2>&1; then
        echo "Successfully connected to $host"
    else
        echo "Failed to connect to $host"
        echo "$host" >> "$failed_connections"
    fi
}

# Extract hostnames from SSH config
hosts=$(grep "^Host " ~/.ssh/config | awk '{print $2}' | grep -v "\*")

# Test connection for each host
for host in $hosts; do
    test_ssh_connection "$host"
done

# Display failed connections
if [ -s "$failed_connections" ]; then
    echo -e "\nFailed connections:"
    cat "$failed_connections"
else
    echo -e "\nAll connections successful!"
    rm "$failed_connections"
fi
