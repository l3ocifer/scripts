#!/bin/bash

# Prompt for an ID
read -p "Please enter an ID: " user_id

# Check if input is empty
if [ -z "$user_id" ]; then
    echo "Error: No ID provided."
    exit 1
fi

# Define the filename based on the provided ID
filename="$HOME/.ssh/leo-$user_id"

# Check if the file already exists
if [ -f "${filename}" ] || [ -f "${filename}.pub" ]; then
    echo "Error: SSH key for this ID already exists."
    exit 1
fi

# Create the SSH key
ssh-keygen -t ed25519 -C "$user_id" -f "$filename"

echo "SSH key generated successfully and saved as ${filename}"
