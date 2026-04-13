#!/bin/bash

set -euo pipefail

GIT_NAME="workaround"
GIT_EMAIL="workaround@noaa.gov"

dir_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
patch_root="${dir_root}/patches"

usage() {
  cat <<EOF
Usage: $0 [--check] [--abort-on-fail] [--submodule NAME]

Options:
  --check           Only check whether the full patch stack would apply cleanly
  --abort-on-fail   Abort any in-progress git am session on failure
  --submodule NAME  Apply patches only for one submodule (e.g. fv3-jedi, ufo, saber)
  -h, --help        Show this help
EOF
}

CHECK_ONLY="NO"
ABORT_ON_FAIL="NO"
ONLY_SUBMODULE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY="YES"
      shift
      ;;
    --abort-on-fail)
      ABORT_ON_FAIL="YES"
      shift
      ;;
    --submodule)
      ONLY_SUBMODULE="${2:-}"
      if [[ -z "${ONLY_SUBMODULE}" ]]; then
        echo "ERROR: --submodule requires a name"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Map patch directories to submodule directories here.
# Left side: name under patches/
# Right side: relative path to submodule repo
PATCH_TARGETS=(
  "fv3-jedi:sorc/fv3-jedi"
  "ufo:sorc/ufo"
  "saber:sorc/saber"
  "gsibec:sorc/gsibec"
)

have_patches() {
  local patch_dir="$1"
  compgen -G "${patch_dir}"/*.patch > /dev/null
}

ensure_clean_repo() {
  local repo_dir="$1"

  if [[ ! -d "${repo_dir}/.git" && ! -f "${repo_dir}/.git" ]]; then
    echo "ERROR: ${repo_dir} does not appear to be a git repository"
    exit 1
  fi

  if ! git -C "${repo_dir}" diff --quiet || ! git -C "${repo_dir}" diff --cached --quiet; then
    echo "ERROR: ${repo_dir} has uncommitted changes"
    echo "       Refusing to apply patches on a dirty repo"
    exit 1
  fi

  if [[ -n "$(git -C "${repo_dir}" ls-files --others --exclude-standard)" ]]; then
    echo "ERROR: ${repo_dir} has untracked files"
    echo "       Refusing to apply patches with untracked files present"
    exit 1
  fi
}

check_no_in_progress_am() {
  local repo_dir="$1"

  if [[ -d "${repo_dir}/.git/rebase-apply" ]] || git -C "${repo_dir}" am --show-current-patch >/dev/null 2>&1; then
    echo "ERROR: git am appears to already be in progress in ${repo_dir}"
    echo "       Resolve it first, or run: git -C ${repo_dir} am --abort"
    exit 1
  fi
}

patch_subject() {
  local patch_file="$1"
  sed -n 's/^Subject: \[PATCH[^]]*\] //p' "${patch_file}" | head -n 1
}

top_commit_subjects_match_patches() {
  local repo_dir="$1"
  shift
  local patch_files=("$@")
  local patch_count="${#patch_files[@]}"

  local i=0
  local patch_subject_val commit_subject_val

  while [[ $i -lt $patch_count ]]; do
    patch_subject_val="$(patch_subject "${patch_files[$i]}")"
    commit_subject_val="$(git -C "${repo_dir}" log -1 --format=%s HEAD~$((patch_count - i - 1)) 2>/dev/null || true)"
    if [[ "${patch_subject_val}" != "${commit_subject_val}" ]]; then
      return 1
    fi
    i=$((i + 1))
  done

  return 0
}

check_patch_series() {
  local name="$1"
  local repo_dir="$2"
  shift 2
  local patch_files=("$@")
  local patch_count="${#patch_files[@]}"

  local start_ref="HEAD"
  if [[ $patch_count -gt 0 ]] && top_commit_subjects_match_patches "${repo_dir}" "${patch_files[@]}"; then
    start_ref="HEAD~${patch_count}"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"

  echo "Checking full patch series for ${name} from ${start_ref} ..."

  echo "  Patch stack:"
  for patch in "${patch_files[@]}"; do
    echo "    - $(basename "$patch")"
  done

  git -C "${repo_dir}" worktree add --detach "${tmpdir}" "${start_ref}" >/dev/null
  if git -C "${tmpdir}" am "${patch_files[@]}" >/dev/null 2>&1; then
    echo "Check passed for ${name}"
    git -C "${tmpdir}" am --abort >/dev/null 2>&1 || true
    git -C "${repo_dir}" worktree remove --force "${tmpdir}" >/dev/null
  else
    echo "ERROR: Patch series check failed for ${name}"
    echo "       Temporary check tree: ${tmpdir}"
    echo "       To inspect the failing patch there, run:"
    echo "         git -C ${tmpdir} am --show-current-patch=diff"
    echo "       To clean it up after inspection, run:"
    echo "         git -C ${repo_dir} worktree remove --force ${tmpdir}"
    exit 1
  fi
}

apply_patch_series() {
  local name="$1"
  local repo_rel="$2"
  local repo_dir="${dir_root}/${repo_rel}"
  local patch_dir="${patch_root}/${name}"

  if [[ -n "${ONLY_SUBMODULE}" && "${ONLY_SUBMODULE}" != "${name}" ]]; then
    return 0
  fi

  if [[ ! -d "${patch_dir}" ]]; then
    echo "INFO: No patch directory for ${name}, skipping"
    return 0
  fi

  if ! have_patches "${patch_dir}"; then
    echo "INFO: No patch files found for ${name}, skipping"
    return 0
  fi

  echo
  echo "============================================================"
  echo "Processing patches for ${name}"
  echo "  repo   : ${repo_dir}"
  echo "  patches: ${patch_dir}"
  echo "============================================================"

  ensure_clean_repo "${repo_dir}"
  check_no_in_progress_am "${repo_dir}"

  local patch_files=()
  while IFS= read -r -d '' file; do
    patch_files+=("${file}")
  done < <(find "${patch_dir}" -maxdepth 1 -type f -name '*.patch' -print0 | sort -z)

  if [[ "${CHECK_ONLY}" == "YES" ]]; then
    check_patch_series "${name}" "${repo_dir}" "${patch_files[@]}"
    return 0
  fi

  echo "Applying patch series for ${name} ..."
  if git -C "${repo_dir}" \
     -c user.name="${GIT_NAME}" \
     -c user.email="${GIT_EMAIL}" \
     am "${patch_files[@]}"; then
    echo "Applied patches successfully for ${name}"
  else
    local patch_count=${#patch_files[@]}
    echo "ERROR: Failed while applying patches for ${name}"
    echo "       Resolve conflicts in ${repo_dir}, then run:"
    echo "         git -C ${repo_dir} am --continue"
    echo "       or abort with:"
    echo "         git -C ${repo_dir} am --abort"
    echo "       To return to a clean upstream state for this submodule, run:"
    echo "         git -C ${repo_dir} am --abort 2>/dev/null || true"
    if [[ ${patch_count} -gt 0 ]]; then
      echo "         git -C ${repo_dir} reset --hard HEAD~${patch_count}"
    else
      echo "         (no patches to drop)"
    fi
    echo "         git -C ${repo_dir} clean -fd"

    if [[ "${ABORT_ON_FAIL}" == "YES" ]]; then
      echo "Aborting in-progress git am session for ${name} ..."
      git -C "${repo_dir}" am --abort || true
    fi
    exit 1
  fi
}

main() {
  if [[ ! -d "${patch_root}" ]]; then
    echo "INFO: ${patch_root} does not exist, nothing to apply"
    exit 0
  fi

  local entry
  for entry in "${PATCH_TARGETS[@]}"; do
    local name="${entry%%:*}"
    local repo_rel="${entry#*:}"
    apply_patch_series "${name}" "${repo_rel}"
  done

  echo
  echo "All requested patch series processed successfully"
}

main "$@"
