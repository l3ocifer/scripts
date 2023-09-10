#!/bin/bash

# Prompt the user for the private key path
echo "Please enter the path to your private SSH key:"
read key_path

# Check if the provided file exists
if [ ! -f "$key_path" ]; then
    echo "The provided path does not point to a file. Exiting..."
    exit 1
fi

# Generate the public key from the private key and output it
echo "Public key:"
ssh-keygen -y -f "$key_path"

