#!/bin/bash

# Function to update a git repository
update_repo() {
    local dir="$1"
    echo "Entering ${dir}"
    cd "${dir}" || return

    # Check if it's a git repository
    if [ -d ".git" ]; then
        echo "Updating main repository in ${dir}"
        git pull

        # Update submodules
        echo "Updating submodules in ${dir}"
        git submodule update --init --recursive
    else
        echo "${dir} is not a git repository."
    fi

    cd - > /dev/null || return
}

# Check if command line arguments are provided
if [ "$#" -gt 0 ]; then
    for dir in "$@"; do
        if [ -d "$dir" ]; then
            update_repo "$dir"
        else
            echo "Directory $dir does not exist."
        fi
    done
else
    # Loop through each directory in the current path
    for dir in */ ; do
        update_repo "$dir"
    done
fi
