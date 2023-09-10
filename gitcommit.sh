#!/bin/bash
# Get the current branch name
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Check if the branch exists on the remote
if ! git show-ref --quiet refs/remotes/origin/$current_branch; then
    # If it doesn't exist, push to origin with the branch name
    git add -A
    git commit -m "updated"
    git push -u origin $current_branch
else
    # If it does exist, just do a normal push
    git add -A
    git commit -m "updated"
    git push
fi
