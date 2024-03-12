#!/bin/bash

# Navigate to the root directory of your repository
cd "$(git rev-parse --show-toplevel)"

# Ensure .gitmodules exists and is readable
if [[ ! -r .gitmodules ]]; then
    echo ".gitmodules file does not exist or is not readable"
    exit 1
fi

# Read each submodule path and branch from .gitmodules and check out the branch
git config --file .gitmodules --get-regexp path | while read path_key path; do
    branch_key="submodule.$path.branch"
    branch=$(git config --file .gitmodules --get "$branch_key")
    if [ -z "$branch" ]; then
        echo "No branch found for submodule $path"
    else
        echo "Checking out branch '$branch' for submodule '$path'"
        git submodule update --init --recursive "$path"
        cd "$path"
        git checkout "$branch"
        cd - > /dev/null
    fi
done

echo "All submodules are checked out to their specified branches."

