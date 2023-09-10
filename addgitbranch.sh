#!/bin/bash

# Navigate to the git repository (assuming you are already in the repo's root directory)
# If not, uncomment and modify the next line
# cd /path/to/your/git/repo

# Check if inside a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: Not inside a Git repository."
    exit 1
fi

# Prompt the user for the branch name
read -p "Enter the name of the new branch: " branch_name

# Check if branch already exists
if git show-ref --verify --quiet refs/heads/$branch_name; then
    echo "Error: Branch already exists."
    exit 1
fi

# Create and checkout the new branch
git checkout -b $branch_name

# push new branch to remote
git push --set-upstream origin $branch_name

echo "Switched to new branch and updated remote to include: $branch_name"
