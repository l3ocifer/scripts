#!/bin/bash

# Helper function to append file contents to the temporary file
append_to_temp_file() {
    local file_path="$1"
    local temp_file="$2"

    # Validate file (ignore files starting with '.', 'LICENSE', and common build artifacts)
    local filename=$(basename "$file_path")
    if [[ "$filename" =~ ^\. || "$filename" == "LICENSE" || "$filename" =~ ^(yarn\.lock|package-lock\.json|node_modules|dist|build|.next|.cache|.*\.(jpg|jpeg|png|gif|bmp|tiff|ico|svg|webp|mp3|mp4|avi|mov|mkv|exe|dll|bin|iso|zip|tar\.gz|rar|7z|pdf|doc|docx|xls|xlsx|ppt|pptx))$ ]]; then
        echo "Skipping invalid file: $filename"
        return
    fi

    # Check if it's a regular file
    if [[ -f "$file_path" ]]; then
        echo "File: $filename" >> "$temp_file"  # Append the title of the file
        cat "$file_path" >> "$temp_file"
        echo -e "\n" >> "$temp_file"  # Adds a newline to separate contents of different files
    fi
}

# Function to process directories
process_directory() {
    local dir_path="$1"
    local temp_file="$2"
    local include_subdirs="$3"

    # Include subdirectories if requested
    if [[ "$include_subdirs" == "yes" ]]; then
        find "$dir_path" -type f \( \
            ! -path "*/.git/*" ! -path "*/.terraform/*" ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/build/*" ! -path "*/.next/*" ! -path "*/.cache/*" \
            ! -iname "*.jpg" ! -iname "*.jpeg" ! -iname "*.png" ! -iname "*.gif" ! -iname "*.bmp" ! -iname "*.tiff" ! -iname "*.ico" ! -iname "*.svg" ! -iname "*.webp" \
            ! -iname "*.mp3" ! -iname "*.mp4" ! -iname "*.avi" ! -iname "*.mov" ! -iname "*.mkv" ! -iname "*.exe" ! -iname "*.dll" ! -iname "*.bin" ! -iname "*.iso" \
            ! -iname "*.zip" ! -iname "*.tar.gz" ! -iname "*.rar" ! -iname "*.7z" ! -iname "*.pdf" ! -iname "*.doc" ! -iname "*.docx" ! -iname "*.xls" ! -iname "*.xlsx" \
            ! -iname "*.ppt" ! -iname "*.pptx" \
        \) -print0 | while IFS= read -r -d $'\0' file; do
            append_to_temp_file "$file" "$temp_file"
        done
    else
        for file in "$dir_path"/*; do
            if [[ -d "$file" && "$file" =~ (.git|.terraform|node_modules|dist|build|.next|.cache) ]]; then
                echo "Skipping directory: $(basename "$file")"
            else
                append_to_temp_file "$file" "$temp_file"
            fi
        done
    fi
}

# Check if arguments were provided on the command line
if [ "$#" -eq 0 ]; then
    # No arguments, prompt the user
    echo "Enter directories or filenames separated by space:"
    read -a inputs
else
    # Use the provided arguments
    inputs=("$@")
fi

# Ask about including subdirectories
read -p "Include subdirectories? (yes/no) [yes]: " include_subdirs
include_subdirs=${include_subdirs:-yes}

# Prepare a temporary file
temp_file=$(mktemp)

# Process each input
for input in "${inputs[@]}"; do
    # Ensure the path is absolute
    if [[ ! "$input" =~ ^(/|~) ]]; then
        input="${PWD}/${input}"
    fi

    if [ -d "$input" ]; then
        # It's a directory, process accordingly
        process_directory "$input" "$temp_file" "$include_subdirs"
    elif [ -f "$input" ]; then
        # It's a single file, process normally
        append_to_temp_file "$input" "$temp_file"
    else
        echo "Warning: $input is neither a valid file nor a directory."
    fi
done

# Verify if the temporary file has content
if [ ! -s "$temp_file" ]; then
    echo "No valid files were found to copy."
    rm "$temp_file"
    exit 1
fi

# Clipboard copy based on OS
case "$(uname -s)" in
    Darwin)
        cat "$temp_file" | pbcopy
        ;;
    Linux)
        if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
            cat "$temp_file" | clip.exe
        else
            if command -v xclip &> /dev/null; then
                cat "$temp_file" | xclip -selection clipboard
            elif command -v xsel &> /dev/null; then
                cat "$temp_file" | xsel --clipboard
            else
                echo "Error: xclip or xsel not found."
                rm "$temp_file"
                exit 1
            fi
        fi
        ;;
    *)
        echo "Unsupported platform."
        rm "$temp_file"
        exit 1
        ;;
esac

echo "Contents of valid files copied to clipboard."
rm "$temp_file"
