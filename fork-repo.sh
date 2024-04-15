#!/bin/bash

# Ensure GitHub username and access token are set
if [[ -z "$GITHUB_USERNAME" || -z "$GITHUB_ACCESS_TOKEN" ]]; then
    echo "Please set your GITHUB_USERNAME and GITHUB_ACCESS_TOKEN environment variables."
    exit 1
fi

# Prompt user for the existing repository's local path or URL
read -p "Enter the existing repository's local path or clone URL: " repo_source

# Determine whether the input is a local path or a URL
if [[ -d "$repo_source" ]]; then
    echo "Using existing local repository."
    cd "$repo_source"
elif [[ "$repo_source" =~ ^https?:// ]]; then
    echo "Cloning repository from URL..."
    git clone "$repo_source"
    repo_name=$(basename "$repo_source" .git)
    cd "$repo_name"
else
    echo "Invalid repository source. Please enter a valid local path or clone URL."
    exit 1
fi

# Remove the original remote to disconnect from the source repository
git remote remove origin

# Get the new repository name from the user or use the current directory's name
read -p "Enter the new repository name (leave blank to use the current directory's name): " new_repo_name
if [[ -z "$new_repo_name" ]]; then
    new_repo_name=$(basename "$(pwd)")
fi

# Create a new private repository on GitHub using the API
echo "Creating new private repository '$new_repo_name' on GitHub..."
create_repo_response=$(curl -s -u $GITHUB_USERNAME:$GITHUB_ACCESS_TOKEN \
    https://api.github.com/user/repos \
    -d '{"name":"'$new_repo_name'", "private":true}')

# Extract the clone URL of the newly created repository
new_repo_clone_url=$(echo "$create_repo_response" | grep "clone_url" | cut -d '"' -f 4)

# If the repository was successfully created, set it as the new origin and push
if [[ -n "$new_repo_clone_url" ]]; then
    echo "New repository created at $new_repo_clone_url"
    git remote add origin "$new_repo_clone_url"
    git push -u origin master
else
    echo "Failed to create new repository. Please check your GitHub credentials and repository name."
    exit 1
fi

echo "Repository fork completed successfully."
