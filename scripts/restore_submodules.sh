#!/bin/bash
set -e

echo "Starting smart submodule restoration..."

# Iterate over each submodule defined in .gitmodules
git config -f .gitmodules --name-only --get-regexp path | while read path_key; do
    # Extract the submodule name
    name=$(echo "$path_key" | sed 's/^submodule\.//;s/\.path$//')
    
    # Read properties
    path=$(git config -f .gitmodules --get "submodule.$name.path")
    url=$(git config -f .gitmodules --get "submodule.$name.url")
    
    # Get the expected commit hash from the parent repo's tree
    # git ls-tree output: mode type object path
    # e.g., 160000 commit 12345abcdef...  some/path
    expected_commit=$(git ls-tree HEAD "$path" | awk '{print $3}')

    echo "Processing $name..."
    echo "  Path: $path"
    echo "  URL:  $url"
    echo "  Expected Commit: $expected_commit"

    if [ -z "$expected_commit" ]; then
        echo "  WARNING: Could not determine expected commit for $path. Skipping."
        continue
    fi

    # Check if the directory exists and has the correct commit checked out
    current_commit=""
    if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
        pushd "$path" > /dev/null
        current_commit=$(git rev-parse HEAD)
        popd > /dev/null
    fi

    if [ "$current_commit" == "$expected_commit" ]; then
        echo "  Submodule already at correct commit. Skipping."
        continue
    fi

    echo "  Restoring/Updating submodule..."
    
    # Ensure parent directory exists
    mkdir -p "$(dirname "$path")"
    
    # If directory exists but is not a valid git repo or wrong remote, clear it
    if [ -d "$path" ] && [ ! -d "$path/.git" ] && [ ! -f "$path/.git" ]; then
        rm -rf "$path"
    fi

    if [ ! -d "$path" ]; then
        git clone "$url" "$path"
    fi

    # Checkout the specific commit
    pushd "$path" > /dev/null
    git fetch origin  # Ensure we have the latest objects
    git checkout "$expected_commit"
    popd > /dev/null
    
    echo "  Success."
done

# Initialize recursive submodules if any (using standard git command for nested ones as they should be consistent now)
echo "Initializing nested submodules..."
git submodule update --init --recursive

echo "Smart submodule restoration complete."