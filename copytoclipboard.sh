#!/bin/bash

# If no argument is provided, prompt for the filename
if [ "$#" -ne 1 ]; then
    read -p "Please enter the filename: " filename
else
    filename="$1"
fi

# If the provided filename doesn't start with a '/' or '~', assume it's relative to the current directory
if [[ ! "$filename" =~ ^[/~] ]]; then
    filename="${PWD}/${filename}"
fi

# Ensure the file exists
if [[ ! -f "$filename" ]]; then
    echo "Error: File $filename does not exist."
    exit 1
fi

# Determine the platform and use the appropriate clipboard command
case "$(uname -s)" in
    Darwin)
        # macOS
        cat "$filename" | pbcopy
        ;;
    Linux)
        # Check if we're on WSL
        if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
            cat "$filename" | clip.exe
        else
            # Check for xclip or xsel for Linux distros
            if command -v xclip &> /dev/null; then
                cat "$filename" | xclip -selection clipboard
            elif command -v xsel &> /dev/null; then
                cat "$filename" | xsel --clipboard
            else
                echo "Error: xclip or xsel not found."
                exit 1
            fi
        fi
        ;;
    *)
        echo "Unsupported platform."
        exit 1
        ;;
esac

echo "Content of $filename copied to clipboard."
