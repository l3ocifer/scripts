#!/bin/bash

# Check if the user wants to use the current directory and its name for the repository
read -p "Would you like to start the repo in the current directory using its existing name? (y/n): " use_current_dir_choice

if [[ "$use_current_dir_choice" == "y" || "$use_current_dir_choice" == "Y" ]]; then
    # Get the current directory's name without any leading periods
    repo_name=$(basename $(pwd) | sed 's/^\.//')
else
    # Get the repository name from user input
    read -p "Enter a repository name: " repo_name

    # Prompt the user for repository visibility
    echo "Choose the repository visibility:"
    echo "1. Private"
    echo "2. Public"
    read -p "Enter your choice (1/2): " repo_visibility_choice

    while [[ "$repo_visibility_choice" != "1" && "$repo_visibility_choice" != "2" ]]; do
        echo "Invalid input. Please enter '1' or '2'."
        read -p "Enter your choice (1/2): " repo_visibility_choice
    done

    repo_visibility="private"
    if [ "$repo_visibility_choice" = "2" ]; then
        repo_visibility="public"
    fi

    # Prompt the user to choose an existing or new subdirectory
    echo "Choose an existing subdirectory or create a new one:"
    select dir in ~/git/*/ "Create new directory"; do
        if [ "$dir" = "Create new directory" ]; then
            read -p "Enter a new subdirectory name: " subdir_name
            mkdir -p ~/git/$subdir_name
            cd ~/git/$subdir_name
            mkdir $repo_name
            cd $repo_name
            break
        elif [ -d "$dir" ]; then
            cd "$dir"
            mkdir $repo_name
            cd $repo_name
            break
        else
            echo "Invalid selection"
        fi
    done
fi

# Create the local repository
git init

# Check if "test.txt" exists. If not, create it.
if [[ ! -f "test.txt" ]]; then
    echo "testing" > test.txt
fi

git add .
git commit -m "Initial commit"

## Create a new repository on GitHub and push changes to it
curl -u $GITHUB_USERNAME:$GITHUB_ACCESS_TOKEN https://api.github.com/user/repos -d '{"name":"'$repo_name'", "private":'$( [ "$repo_visibility" = "private" ] && echo 'true' || echo 'false')'}'
git remote add origin https://github.com/$GITHUB_USERNAME/$repo_name.git
git push -u origin master
