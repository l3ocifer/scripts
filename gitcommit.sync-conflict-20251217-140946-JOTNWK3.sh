#!/bin/bash

# Get the current branch name
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Default commit message
default_message="updated"

# Prompt the user for a commit message, default to "updated" if none is given
read -p "Enter commit message (default: $default_message): " commit_message
commit_message=${commit_message:-$default_message}

# Function to commit and push submodules
update_submodules() {
    echo "Checking for submodules..."
    
    # Check if there are any submodules
    if [ -f ".gitmodules" ]; then
        echo "Found submodules, updating them..."
        
        # Update submodules to latest commits
        git submodule foreach --recursive '
            echo "Processing submodule: $name"
            git add -A
            if ! git diff --cached --quiet; then
                git commit -m "'"$commit_message"'" || echo "Nothing to commit in $name"
                git push || echo "Failed to push $name - may need to set upstream"
            else
                echo "No changes in submodule $name"
            fi
        '
        
        # Update the parent repo with new submodule commits
        echo "Updating parent repository with submodule changes..."
        git add -A
    else
        echo "No submodules found."
        git add -A
    fi
}

# Update submodules first
update_submodules

# Check if the branch exists on the remote
if ! git show-ref --quiet refs/remotes/origin/$current_branch; then
    # If it doesn't exist, push to origin with the branch name
    git commit -m "$commit_message"
    git push -u origin $current_branch
else
    # If it does exist, just do a normal push
    git commit -m "$commit_message"
    git push
fi

echo "Commit and push completed for main repository and all submodules."
