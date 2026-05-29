#!/bin/bash

# Function to pull latest changes and update submodules
pull_with_submodules() {
    echo "Pulling latest changes from remote..."
    
    # Get current branch name
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Current branch: $current_branch"
    
    # Pull latest changes from remote
    if ! git pull; then
        echo "Failed to pull from remote. Please resolve conflicts manually."
        return 1
    fi
    
    # Check if there are any submodules
    if [ -f ".gitmodules" ]; then
        echo "Found submodules, updating them..."
        
        # Initialize and update all submodules recursively
        echo "Initializing and updating submodules..."
        if ! git submodule update --init --recursive; then
            echo "Failed to update submodules. Please check submodule configurations."
            return 1
        fi
        
        # Pull latest changes for each submodule
        echo "Pulling latest changes for all submodules..."
        git submodule foreach --recursive '
            echo "Updating submodule: $name"
            current_sub_branch=$(git rev-parse --abbrev-ref HEAD)
            echo "  Current branch: $current_sub_branch"
            
            # Check for uncommitted changes (including untracked files)
            if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
                echo "  Warning: Submodule $name has uncommitted/untracked changes"
                echo "  Stashing changes (including untracked files) before pulling..."
                git stash push -u -m "Auto-stash before pull - $(date)" || {
                    echo "  Failed to stash changes, trying to add and stash..."
                    git add -A
                    git stash push -m "Auto-stash before pull - $(date)" || {
                        echo "  Could not stash changes, skipping pull for this submodule"
                        continue
                    }
                }
            fi
            
            # If we are on a detached HEAD, try to checkout main or master
            if [ "$current_sub_branch" = "HEAD" ]; then
                echo "  Submodule is in detached HEAD state, checking out main branch..."
                if git show-ref --verify --quiet refs/remotes/origin/main; then
                    git checkout main
                elif git show-ref --verify --quiet refs/remotes/origin/master; then
                    git checkout master
                else
                    echo "  Warning: Could not find main or master branch for $name"
                fi
            fi
            
            # Pull latest changes
            if ! git pull; then
                echo "  Warning: Failed to pull latest changes for submodule $name"
            else
                echo "  Successfully updated submodule $name"
            fi
            
            # Automatically restore stashed changes
            if git stash list | grep -q "Auto-stash before pull"; then
                echo "  Restoring previously stashed changes..."
                if git stash pop; then
                    echo "  Successfully restored local changes in $name"
                else
                    echo "  Warning: Failed to restore stashed changes in $name - you may need to resolve conflicts manually"
                    echo "  Use '\''git stash list'\'' and '\''git stash pop'\'' to restore them manually"
                fi
            fi
        '
        
        echo "All submodules updated successfully."
    else
        echo "No submodules found in this repository."
    fi
    
    echo "Pull operation completed successfully!"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository."
    exit 1
fi

# Execute the pull function
pull_with_submodules
