#!/bin/bash
# GitHub snapshot handling library with git submodule support
# Handles both ZIP snapshots and git clones for implementations requiring submodules

# Source formatting library if not already loaded
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_this_script_dir}/lib-output-formatting.sh"
fi

# Get list of required GitHub sources from images.yaml
# Returns: TSV with commit, repo, requiresSubmodules flag
# Format: commit<TAB>repo<TAB>requiresSubmodules
get_required_github_sources() {
  if [ ! -f images.yaml ]; then
    print_error "Error: images.yaml not found" >&2
    return 1
  fi

  yq eval '.implementations[] |
    select(.source.type == "github") |
    .source.commit + "\t" + .source.repo + "\t" + (.source.requiresSubmodules // false)' \
    images.yaml
  }

# Copy GitHub sources to snapshot directory
# Handles both ZIP snapshots and git clones with submodules
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: cache_dir - Source cache directory
# Returns: 0 on success, 1 if errors
copy_github_sources_to_snapshot() {
  local snapshot_dir="$1"
  local cache_dir="$2"
  indent

  mkdir -p "${snapshot_dir}/snapshots"
  mkdir -p "${snapshot_dir}/git-repos"

  local copied_zips=0
  local copied_git=0
  local missing=0

  while IFS=$'\t' read -r commit repo requires_submodules; do
    local repo_name=$(basename "${repo}")

    if [ "${requires_submodules}" == "true" ]; then
      # Copy git clone (includes submodules)
      local git_dir="${cache_dir}/git-repo/${repo_name}-${commit}"
      if [ -d "${git_dir}" ]; then
        cp -r "${git_dir}" "${snapshot_dir}/git-repo/"
        copied_git=$((${copied_git} + 1))
      else
        print_error "Warning: Missing git clone for ${repo_name} (commit: ${commit:0:8})"
        missing=$((${missing} + 1))
      fi
    else
      # Copy ZIP snapshot
      if [ -f "${cache_dir}/snapshots/${commit}.zip" ]; then
        cp "${cache_dir}/snapshots/${commit}.zip" "${snapshot_dir}/snapshots/"
        copied_zips=$((${copied_zips} + 1))
      else
        print_error "Warning: Missing ZIP snapshot for commit ${commit:0:8}"
        missing=$((${missing} + 1))
      fi
    fi
  done < <(get_required_github_sources)

  # Report results
  if [ ${copied_zips} -gt 0 ]; then
    print_success "Copied ${copied_zips} ZIP snapshots"
  fi

  if [ ${copied_git} -gt 0 ]; then
    print_success "Copied ${copied_git} git clones (with submodules)"
  fi

  if [ ${missing} -gt 0 ]; then
    print_error "Warning: ${missing} sources missing from cache"
    unindent
    return 1
  fi

  unindent
  return 0
}

# Check if implementation requires git clone (has submodules)
# Args:
#   $1: impl_id - Implementation ID to check
# Returns: 0 if requires git, 1 if ZIP is sufficient
impl_requires_git_clone() {
  local impl_id="$1"

  local requires=$(yq eval ".implementations[] |
    select(.id == \"${impl_id}\") |
    .source.requiresSubmodules // false" images.yaml)

  [ "${requires}" == "true" ]
}

# Clean up empty source directories in snapshot
# Args:
#   $1: snapshot_dir - Snapshot directory
cleanup_empty_source_dirs() {
  local snapshot_dir="$1"

  # Remove empty snapshots/ directory
  if [ -d "${snapshot_dir}/snapshots" ] && [ ! "$(ls -A "${snapshot_dir}/snapshots" 2>/dev/null)" ]; then
    rmdir "${snapshot_dir}/snapshots"
  fi

  # Remove empty git-repos/ directory
  if [ -d "${snapshot_dir}/git-repos" ] && [ ! "$(ls -A "${snapshot_dir}/git-repos" 2>/dev/null)" ]; then
    rmdir "${snapshot_dir}/git-repos"
  fi
}
