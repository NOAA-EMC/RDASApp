#!/usr/bin/env bash
# submodule-diff.sh
# Print old -> new SHAs for each submodule in a clean table.
# Usage:
#   ./submodule-diff.sh           # show only changed submodules (short SHAs)
#   ./submodule-diff.sh --all     # include unchanged submodules
#   ./submodule-diff.sh --long    # use full 40-char SHAs
#   ./submodule-diff.sh --all --long

set -euo pipefail

SHOW_ALL=0
LONG=0
for arg in "$@"; do
  case "$arg" in
    --all)  SHOW_ALL=1 ;;
    --long) LONG=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ ! -f .gitmodules ]]; then
  echo "No .gitmodules found. Run this from the root of your superproject." >&2
  exit 1
fi

# Iterate submodules listed in .gitmodules
while IFS= read -r line; do
  # line looks like: "submodule.NAME.path PATH"
  key=${line%% *}                      # submodule.NAME.path
  name=${key#submodule.}; name=${name%.path}
  path=${line#* }                      # PATH

  # Old = SHA recorded at HEAD for the gitlink in the superproject
  old_full=$(git ls-tree -d HEAD -- "$path" | awk '{print $3}')
  # If the submodule was just added or HEAD doesn't track it yet, old may be empty
  [[ -z "${old_full:-}" ]] && old_full="(none)"

  # New = current HEAD of the submodule working tree
  if ! new_full=$(git -C "$path" rev-parse HEAD 2>/dev/null); then
    # uninitialized submodule
    new_full="(uninitialized)"
  fi

  if [[ "$LONG" -eq 1 ]]; then
    old="$old_full"; new="$new_full"
  else
    # Shorten to 7 chars when possible
    [[ "$old_full" =~ ^[0-9a-f]{7,40}$ ]] && old=${old_full:0:7} || old="$old_full"
    [[ "$new_full" =~ ^[0-9a-f]{7,40}$ ]] && new=${new_full:0:7} || new="$new_full"
  fi

  # Print only changed unless --all
  if [[ "$SHOW_ALL" -eq 1 || "$old_full" != "$new_full" ]]; then
    printf "%-14s %s -> %s\n" "${name}:" "$old" "$new"
  fi
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$')

