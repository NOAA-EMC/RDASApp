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
  "mpas-jedi:sorc/mpas-jedi"
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

check_patch_series() {
  local name="$1"
  local repo_dir="$2"
  local base_file="$3"
  shift 3
  local patch_files=("$@")

  local start_commit
  if [[ -f "${base_file}" ]]; then
    start_commit="$(head -n 1 "${base_file}")"
    echo "Using base commit from ${base_file}: ${start_commit}"
  else
    start_commit="$(git -C "${repo_dir}" rev-parse HEAD)"
    echo "Recording base commit to ${base_file}: ${start_commit}"
    {
      echo "${start_commit}"
      echo "date=$(date)"
      echo "repo=${name}"
    } > "${base_file}"
  fi

  if ! git -C "${repo_dir}" cat-file -e "${start_commit}^{commit}" 2>/dev/null; then
    echo "ERROR: Base commit ${start_commit} from ${base_file} does not exist in ${repo_dir}"
    exit 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"

  echo "Checking full patch series for ${name} from ${start_commit} ..."

  echo "  Patch stack:"
  local patch
  for patch in "${patch_files[@]}"; do
    echo "    - $(basename "$patch")"
  done

  git -C "${repo_dir}" worktree add --detach "${tmpdir}" "${start_commit}" >/dev/null
  if git -C "${tmpdir}" \
       -c user.name="${GIT_NAME}" \
       -c user.email="${GIT_EMAIL}" \
       am "${patch_files[@]}" >/dev/null 2>&1; then
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
  local base_file="${patch_dir}/.base_commit"

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

  # Handle dirty repo safely
  local stash_ref=""
  if [[ -n "$(git -C "${repo_dir}" status --porcelain)" ]]; then
    echo "WARNING: ${repo_dir} has local changes"
    echo "Stashing them before applying patches..."
    stash_ref=$(git -C "${repo_dir}" stash push -u -m "apply_patches.sh auto-stash" | awk '{print $1}')
  fi

  ensure_clean_repo "${repo_dir}"
  check_no_in_progress_am "${repo_dir}"

  local patch_files=()
  while IFS= read -r -d '' file; do
    patch_files+=("${file}")
  done < <(find "${patch_dir}" -maxdepth 1 -type f -name '*.patch' -print0 | sort -z)

  if [[ "${CHECK_ONLY}" == "YES" ]]; then
    check_patch_series "${name}" "${repo_dir}" "${base_file}" "${patch_files[@]}"
    return 0
  fi

  local start_commit
  if [[ -f "${base_file}" ]]; then
    start_commit="$(head -n 1 "${base_file}")"
    echo "Using base commit from ${base_file}: ${start_commit}"
  else
    start_commit="$(git -C "${repo_dir}" rev-parse HEAD)"
    echo "Recording base commit to ${base_file}: ${start_commit}"
    echo "${start_commit}" > "${base_file}"
    echo "date=$(date)" >> "${base_file}"
    echo "repo=${name}" >> "${base_file}"
  fi

  if ! git -C "${repo_dir}" cat-file -e "${start_commit}^{commit}" 2>/dev/null; then
    echo "ERROR: Base commit ${start_commit} from ${base_file} does not exist in ${repo_dir}"
    exit 1
  fi

  echo "Resetting ${repo_dir} to base commit ${start_commit} ..."
  git -C "${repo_dir}" am --abort 2>/dev/null || true
  git -C "${repo_dir}" reset --hard "${start_commit}"
  git -C "${repo_dir}" clean -fd

  echo "Applying patch series for ${name} ..."
  echo "  start commit: ${start_commit}"
  if git -C "${repo_dir}" \
     -c user.name="${GIT_NAME}" \
     -c user.email="${GIT_EMAIL}" \
     am "${patch_files[@]}"; then
    echo "Applied patches successfully for ${name}"
  else
    echo "ERROR: Failed while applying patches for ${name}"
    echo "       Resolve conflicts in ${repo_dir}, then run:"
    echo "         git -C ${repo_dir} am --continue"
    echo "       or abort with:"
    echo "         git -C ${repo_dir} am --abort"
    echo "       To return to the stored base commit for this patch set, run:"
    echo "         git -C ${repo_dir} am --abort 2>/dev/null || true"
    echo "         git -C ${repo_dir} reset --hard ${start_commit}"
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
