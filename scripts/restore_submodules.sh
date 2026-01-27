#!/bin/bash
set -e

echo "Starting manual submodule restoration..."

# Iterate over each submodule defined in .gitmodules
git config -f .gitmodules --name-only --get-regexp path | while read path_key; do
    # Extract the submodule name
    name=$(echo "$path_key" | sed 's/^submodule\.//;s/\.path$//')
    
    # Read properties
    path=$(git config -f .gitmodules --get "submodule.$name.path")
    url=$(git config -f .gitmodules --get "submodule.$name.url")
    branch=$(git config -f .gitmodules --get "submodule.$name.branch" || echo "")

    # Check if the directory is missing or empty
    if [ ! -d "$path" ] || [ -z "$(ls -A "$path" 2>/dev/null)" ]; then
        echo "------------------------------------------------"
        echo "Restoring missing submodule: $name"
        echo "  Path: $path"
        echo "  URL:  $url"
        echo "  Branch: ${branch:-HEAD}"
        
        # Ensure parent directory exists
        mkdir -p "$(dirname "$path")"
        
        # Remove empty dir if it exists to avoid clone errors
        rm -rf "$path"
        
        # Clone
        if [ -n "$branch" ]; then
            git clone --depth 1 --recursive --branch "$branch" "$url" "$path"
        else
            git clone --depth 1 --recursive "$url" "$path"
        fi
    else
        echo "Submodule $name appears to exist at $path. Skipping."
    fi
done

echo "Manual submodule restoration complete."
