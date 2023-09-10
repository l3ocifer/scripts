#!/bin/bash

# Prompt the user for the path to the public key, defaulting to ~/.ssh/
read -e -p "Enter the name or path to your SSH public key (default directory: ~/.ssh/): " pubkey_input

# If the user provides a simple name (without slashes), prefix with ~/.ssh/
if [[ "$pubkey_input" != */* ]]; then
    pubkey_path="$HOME/.ssh/$pubkey_input"
else
    pubkey_path="$pubkey_input"
fi

# Check if the provided path exists and is a regular file
if [[ -f "$pubkey_path" ]]; then
    # Display the SHA256 fingerprint of the public key
    ssh-keygen -lf "$pubkey_path" -E sha256
else
    echo "Error: The provided path either doesn't exist or is not a regular file."
fi
