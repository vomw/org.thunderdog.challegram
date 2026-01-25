#!/bin/bash
set -e

echo "Starting robust submodule restoration..."

# Function to check if a directory is empty
is_empty() {
    [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

# Iterate over each submodule defined in .gitmodules
git config -f .gitmodules --name-only --get-regexp path | while read path_key; do
    # Extract the submodule name
    name=$(echo "$path_key" | sed 's/^submodule\.//;s/\.path$//')
    
    # Read properties
    path=$(git config -f .gitmodules --get "submodule.$name.path")
    url=$(git config -f .gitmodules --get "submodule.$name.url")
    branch=$(git config -f .gitmodules --get "submodule.$name.branch" || echo "")

    echo "Checking submodule: $name ($path)"

    # Check if the directory is missing or empty
    if [ ! -d "$path" ] || is_empty "$path"; then
        echo "  -> Missing or empty. Restoring..."
        
        # Ensure parent directory exists
        mkdir -p "$(dirname "$path")"
        
        # Remove dir if it exists but is empty/broken
        rm -rf "$path"
        
        # Clone
        if [ -n "$branch" ]; then
            echo "  -> Cloning branch: $branch"
            git clone --depth 1 --recursive --branch "$branch" "$url" "$path"
        else
            echo "  -> Cloning HEAD"
            git clone --depth 1 --recursive "$url" "$path"
        fi
    else
        echo "  -> Exists. Attempting update..."
        # Try to update it if it exists
        git submodule update --init --recursive "$path" || echo "  -> Update failed (non-fatal, continuing)"
    fi
done

echo "Running final recursive update..."
git submodule update --init --recursive || true

echo "Verifying 'opus'..."
if [ -d "app/jni/third_party/opus" ]; then
    echo "  -> app/jni/third_party/opus exists."
    ls -A "app/jni/third_party/opus" | head -n 5
else
    echo "  -> app/jni/third_party/opus STILL MISSING!"
    exit 1
fi

echo "Robust submodule restoration complete."
