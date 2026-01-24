#!/usr/bin/env bash
# Shared image building functions for all test suites
# Used by build-single-image.sh

# Check if Docker image exists
# Usage: docker_image_exists <image_name>
# Returns: 0 if exists, 1 if not
docker_image_exists() {
  local image_name="$1"
  docker image inspect "${image_name}" >/dev/null 2>&1
}

# Helper function to build images from a YAML section (implementations or baselines)
build_images_from_section() {
  local section="$1"  # "implementations", "baselines", "routers", etc
  local filter="${2:-}" # Optional: pipe-separated filter (e.g., "go-v0.45|rust-v0.56")
  local force_image_rebuild="${3:-false}"

  local count=$(yq eval ".${section} | length" "${IMAGES_YAML}")

  for ((i=0; i<count; i++)); do
    local impl_id=$(yq eval ".${section}[$i].id" "${IMAGES_YAML}")
    local source_type=$(yq eval ".${section}[$i].source.type" "${IMAGES_YAML}")

    # Apply filter if specified
    if [ -n "${filter}" ]; then
      match_found=false
      IFS='|' read -ra FILTER_PATTERNS <<< "${filter}"
      for pattern in "${FILTER_PATTERNS[@]}"; do
        case "${impl_id}" in
          "${pattern}")
            match_found=true
            break
            ;;
        esac
      done
      if [ "${match_found}" == "false" ]; then
        continue
      fi
    fi

    local image_name=$(get_image_name "${TEST_TYPE}" "${section}" "${impl_id}")

    # Check if image already exists (for local builds only)
    if [ "${force_image_rebuild}" != "true" ] && docker_image_exists "${image_name}"; then
      print_success "${image_name} (already built)"
      continue
    fi

    # Create YAML file for this build
    local yaml_file="${CACHE_DIR}/build-yamls/docker-build-${TEST_TYPE}-${impl_id}.yaml"

    cat > "${yaml_file}" <<EOF
imageName: ${image_name}
sourceType: ${source_type}
cacheDir: ${CACHE_DIR}
forceRebuild: ${force_image_rebuild}
EOF

    # Add source-specific parameters
    case "${source_type}" in
      github)
        local repo=$(yq eval ".${section}[$i].source.repo" "${IMAGES_YAML}")
        local commit=$(yq eval ".${section}[$i].source.commit" "${IMAGES_YAML}")
        local dockerfile=$(yq eval ".${section}[$i].source.dockerfile" "${IMAGES_YAML}")
        local build_context=$(yq eval ".${section}[$i].source.buildContext // \".\"" "${IMAGES_YAML}")
        local requires_submodules=$(yq eval ".${section}[$i].source.requiresSubmodules // false" "${IMAGES_YAML}")
        local patch_path=$(yq eval ".${section}[$i].source.patchPath // \"\"" "${IMAGES_YAML}")
        local patch_file=$(yq eval ".${section}[$i].source.patchFile // \"\"" "${IMAGES_YAML}")

        cat >> "${yaml_file}" <<EOF

github:
  repo: ${repo}
  commit: ${commit}
  dockerfile: ${dockerfile}
  buildContext: ${build_context}
  patchPath: ${patch_path}
  patchFile: ${patch_file}

requiresSubmodules: ${requires_submodules}
EOF
      ;;

      local)
        local local_path=$(yq eval ".${section}[$i].source.path" "${IMAGES_YAML}")
        local dockerfile=$(yq eval ".${section}[$i].source.dockerfile // \"Dockerfile\"" "${IMAGES_YAML}")
        local patch_path=$(yq eval ".${section}[$i].source.patchPath // \"\"" "${IMAGES_YAML}")
        local patch_file=$(yq eval ".${section}[$i].source.patchFile // \"\"" "${IMAGES_YAML}")

        cat >> "${yaml_file}" <<EOF

local:
  path: ${local_path}
  dockerfile: ${dockerfile}
  patchPath: ${patch_path}
  patchFile: ${patch_file}
EOF
      ;;

      browser)
        local base_image=$(yq eval ".${section}[$i].source.baseImage" "${IMAGES_YAML}")
        local browser=$(yq eval ".${section}[$i].source.browser" "${IMAGES_YAML}")
        local dockerfile=$(yq eval ".${section}[$i].source.dockerfile" "${IMAGES_YAML}")
        local build_context=$(dirname "${dockerfile}")
        local patch_path=$(yq eval ".${section}[$i].source.patchPath // \"\"" "${IMAGES_YAML}")
        local patch_file=$(yq eval ".${section}[$i].source.patchFile // \"\"" "${IMAGES_YAML}")
        local base_image_name=$(get_image_name "${TEST_TYPE}" "${section}" "${base_image}")

        cat >> "${yaml_file}" <<EOF

browser:
  baseImage: ${base_image_name}
  browser: ${browser}
  dockerfile: ${dockerfile}
  buildContext: ${build_context}
  patchPath: ${patch_path}
  patchFile: ${patch_file}
EOF
      ;;

      *)
        print_error "Unknown source type: ${source_type}"
        exit 1
      ;;
    esac

    bash "${SCRIPT_LIB_DIR}/build-single-image.sh" "${yaml_file}" || {
      print_error "Local build failed for ${impl_id}"
        exit 1
    }
  done
}

# Download GitHub snapshot to cache
download_github_snapshot() {
  local repo="$1"
  local commit="$2"
  local cache_dir="$3"

  local snapshot_file="${cache_dir}/snapshots/${commit}.zip"

  if [ ! -f "${snapshot_file}" ]; then
    print_error "[MISS] Downloading snapshot..."
    local repo_url="https://github.com/${repo}/archive/${commit}.zip"
    wget -q -O "${snapshot_file}" "${repo_url}" || {
      print_error "Failed to download snapshot"
      return 1
    }
    indent
    print_success "Added to cache: ${snapshot_file}"
    unindent
  else
    print_success "[HIT] Using cached snapshot: ${snapshot_file}"
  fi

  echo "${snapshot_file}"
}

# Extract GitHub snapshot
extract_github_snapshot() {
  local snapshot_file="$1"
  local repo_name="$2"
  local commit="$3"

  local work_dir=$(mktemp -d)
  print_message "Extracting snapshot..."
  indent
  print_message "${work_dir}"
  unzip -q "${snapshot_file}" -d "${work_dir}" || {
    print_error "Failed to extract snapshot"
    rm -rf "${work_dir}"
    unindent
    return 1
  }

  local extracted_dir="${work_dir}/${repo_name}-${commit}"
  if [ ! -d "${extracted_dir}" ]; then
    print_error "Expected directory not found: ${extracted_dir}"
    rm -rf "${work_dir}"
    unindent
    return 1
  fi

  unindent
  echo "${work_dir}"  # Caller must clean up with: rm -rf "$work_dir"
}

# Apply patch file to build context if specified
# Args:
#   $1: target_dir - Directory to apply patch IN (the build context)
#   $2: patch_path - Directory containing patch file (relative to run.sh PWD or absolute)
#   $3: patch_file - Patch filename (no path separators allowed)
# Returns: 0 on success, 1 on failure
apply_patch_if_specified() {
  local target_dir="$1"
  local patch_path="$2"
  local patch_file="$3"

  print_message "Patching..."
  indent

  # Skip if no patch specified (both must be present)
  if [ -z "${patch_path}" ] || [ "${patch_path}" == "null" ]; then
    print_error "Patch path not specified"
    unindent
    return 0
  fi
  if [ -z "${patch_file}" ] || [ "${patch_file}" == "null" ]; then
    print_error "Patch file not specified"
    unindent
    return 0
  fi

  # Validate patch_file doesn't contain path separators
  if [[ "${patch_file}" == *"/"* ]] || [[ "${patch_file}" == *"\\"* ]]; then
    print_error "Invalid patchFile: must be filename only: ${patch_file}"
    unindent
    return 1
  fi

  # Resolve patch_path (handle absolute vs relative to PWD)
  local resolved_patch_path
  if [[ "${patch_path}" == /* ]]; then
    resolved_patch_path="${patch_path}"
  else
    resolved_patch_path="$(pwd)/${patch_path}"
  fi

  # Full path to patch file
  local full_patch_path="${resolved_patch_path}/${patch_file}"

  # Validate patch file exists
  if [ ! -f "${full_patch_path}" ]; then
    print_error "Patch file not found: ${full_patch_path}"
    unindent
    return 1
  fi

  # Validate target directory exists and is writable
  if [ ! -d "${target_dir}" ]; then
    print_error "Target directory not found: ${target_dir}"
    unindent
    return 1
  fi
  if [ ! -w "${target_dir}" ]; then
    print_error "Target directory not writable: ${target_dir}"
    unindent
    return 1
  fi

  print_message "Applying patch: ${patch_file}"
  print_message "From: ${full_patch_path}"
  print_message "To: ${target_dir}"

  # Apply patch from inside target directory
  # Use: cd <target> && patch < <patchfile>
  if ! (cd "${target_dir}" && patch -p1 < "${full_patch_path}") 2>&1 | sed 's/^/  /'; then
    print_error "Failed to apply patch"
    unindent
    return 1
  fi

  print_success "Patch applied successfully"
  unindent
  return 0
}

# Clone GitHub repo with submodules
# Returns path to work directory (caller must clean up)
clone_github_repo_with_submodules() {
  local repo="$1"
  local commit="$2"
  local cache_dir="$3"

  local repo_name=$(basename "${repo}")
  local cache_key="${repo_name}-${commit}"
  local cached_clone="${cache_dir}/git-repos/${cache_key}"

  # Check if already cloned and cached
  if [ -d "${cached_clone}" ]; then
    print_success "[HIT] Using cached git clone: ${commit}"

    # Copy to temp directory (avoid modifying cache)
    local work_dir=$(mktemp -d)
    cp -r "${cached_clone}" "${work_dir}/${repo_name}"
    echo "${work_dir}"
    return 0
  fi

  print_message "[MISS] Cloning repo with submodules..."

  # Create work directory
  local work_dir=$(mktemp -d)
  local clone_dir="${work_dir}/${repo_name}"

  # Clone the repository
  print_message "Cloning ${repo}..."
  if ! git clone --depth 1 "https://github.com/${repo}.git" "${clone_dir}" 2>&1 | sed 's/^/    /' >&2; then
    print_error "Failed to clone repository"
    rm -rf "${work_dir}"
    return 1
  fi

  # Checkout specific commit (need to unshallow for specific commit)
  print_message "Fetching commit ${commit}..."
  cd "${clone_dir}"

  # First, try to checkout directly (might already have it from shallow clone)
  if ! git checkout "${commit}" 2>/dev/null; then
    # If not, fetch the specific commit
    if ! git fetch --depth 1 origin "${commit}" 2>&1 | sed 's/^/    /' >&2; then
      print_error "Failed to fetch commit"
      cd - > /dev/null
      rm -rf "${work_dir}"
      return 1
    fi

    if ! git checkout "${commit}" 2>&1 | sed 's/^/    /' >&2; then
      print_error "Failed to checkout commit"
      cd - > /dev/null
      rm -rf "${work_dir}"
      return 1
    fi
  fi

  # Initialize and update submodules
  print_message "Initializing submodules..."
  if ! git submodule update --init --recursive --depth 1 2>&1 | sed 's/^/    /' >&2; then
    print_error "Failed to initialize submodules"
    cd - > /dev/null
    rm -rf "${work_dir}"
    return 1
  fi

  cd - > /dev/null

  # Cache the clone for future use
  print_message "Caching git clone..."
  mkdir -p "${cache_dir}/git-repos"
  cp -r "${clone_dir}" "${cached_clone}"
  print_success "Added to cache: ${cached_clone}"

  echo "${work_dir}"  # Return work_dir (caller must clean up)
}

# Build from GitHub source
build_from_github() {
  local yaml_file="$1"

  print_message "YAML: ${yaml_file}"

  local image_name=$(yq eval '.imageName' "${yaml_file}")
  local repo=$(yq eval '.github.repo' "${yaml_file}")
  local commit=$(yq eval '.github.commit' "${yaml_file}")
  local dockerfile=$(yq eval '.github.dockerfile' "${yaml_file}")
  local build_context=$(yq eval '.github.buildContext' "${yaml_file}")
  local cache_dir=$(yq eval '.cacheDir' "${yaml_file}")
  local patch_path=$(yq eval '.github.patchPath // ""' "${yaml_file}")
  local patch_file=$(yq eval '.github.patchFile // ""' "${yaml_file}")

  print_message "Repo: ${repo}"
  print_message "Commit: ${commit:0:8}"

  # Download snapshot
  local repo_name=$(basename "${repo}")
  local snapshot_file=$(download_github_snapshot "${repo}" "${commit}" "${cache_dir}") || return 1

  # Extract
  local work_dir=$(extract_github_snapshot "${snapshot_file}" "${repo_name}" "${commit}") || return 1
  local extracted_dir="${work_dir}/${repo_name}-${commit}"

  # Determine build context
  local context_dir
  if [ "${build_context}" == "." ]; then
    context_dir="${extracted_dir}"
  else
    context_dir="${extracted_dir}/${build_context}"
  fi

  # Apply patch if specified
  if ! apply_patch_if_specified "${context_dir}" "${patch_path}" "${patch_file}"; then
    rm -rf "${work_dir}"
    return 1
  fi

  # Build
  print_message "Building Docker image..."
  if ! (cd "${context_dir}" && docker build -f "${extracted_dir}/${dockerfile}" --build-arg HOST_OS="${HOST_OS}" -t "${image_name}" .); then
    print_error "Docker build failed"
    rm -rf "${work_dir}"
    return 1
  fi

  #rm -rf "$work_dir"
  return 0
}

# Build from GitHub source with submodules support
build_from_github_with_submodules() {
  local yaml_file="$1"

  local image_name=$(yq eval '.imageName' "${yaml_file}")
  local repo=$(yq eval '.github.repo' "${yaml_file}")
  local commit=$(yq eval '.github.commit' "${yaml_file}")
  local dockerfile=$(yq eval '.github.dockerfile' "${yaml_file}")
  local build_context=$(yq eval '.github.buildContext' "${yaml_file}")
  local cache_dir=$(yq eval '.cacheDir' "${yaml_file}")
  local patch_path=$(yq eval '.github.patchPath // ""' "${yaml_file}")
  local patch_file=$(yq eval '.github.patchFile // ""' "${yaml_file}")

  print_message "Repo: ${repo}"
  print_message "Commit: ${commit:0:8}"
  print_message "Method: git clone (submodules enabled)"

  # Clone with submodules
  local work_dir=$(clone_github_repo_with_submodules "${repo}" "${commit}" "${cache_dir}") || return 1
  local repo_name=$(basename "${repo}")
  local cloned_dir="${work_dir}/${repo_name}"

  # Determine build context
  local context_dir
  if [ "${build_context}" == "." ]; then
    context_dir="${cloned_dir}"
  else
    context_dir="${cloned_dir}/${build_context}"
  fi

  # Apply patch if specified
  if ! apply_patch_if_specified "${context_dir}" "${patch_path}" "${patch_file}"; then
    rm -rf "${work_dir}"
    return 1
  fi

  # Build
  print_message "Building Docker image..."
  if ! docker build -f "${cloned_dir}/${dockerfile}" --build-arg HOST_OS="${HOST_OS}" -t "${image_name}" "${context_dir}"; then
    print_error "Docker build failed"
    rm -rf "${work_dir}"
    return 1
  fi

  rm -rf "${work_dir}"
  return 0
}

# Build from local source
build_from_local() {
  local yaml_file="$1"

  local image_name=$(yq eval '.imageName' "${yaml_file}")
  local local_path=$(yq eval '.local.path' "${yaml_file}")
  local dockerfile=$(yq eval '.local.dockerfile' "${yaml_file}")
  local patch_path=$(yq eval '.local.patchPath // ""' "${yaml_file}")
  local patch_file=$(yq eval '.local.patchFile // ""' "${yaml_file}")

  print_message "Path: ${local_path}"

  if [ ! -d "${local_path}" ]; then
    print_error "Local path not found: ${local_path}"
    return 1
  fi

  # If patch specified, create temporary copy (cannot modify user's source)
  local build_path="${local_path}"
  local cleanup_temp=false

  if [ -n "${patch_path}" ] && [ "${patch_path}" != "null" ] && \
     [ -n "${patch_file}" ] && [ "${patch_file}" != "null" ]; then
    print_message "Creating temporary copy for patching..."
    local temp_dir=$(mktemp -d)
    cp -r "${local_path}/." "${temp_dir}/"
    build_path="${temp_dir}"
    cleanup_temp=true

    # Apply patch to temporary copy
    if ! apply_patch_if_specified "${build_path}" "${patch_path}" "${patch_file}"; then
      rm -rf "${temp_dir}"
      return 1
    fi
  fi

  print_message "Building Docker image..."
  if ! docker build -f "${build_path}/${dockerfile}" --build-arg HOST_OS="${HOST_OS}" -t "${image_name}" "${build_path}"; then
    print_error "Docker build failed"
    if [ "${cleanup_temp}" == "true" ]; then
      rm -rf "${build_path}"
    fi
    return 1
  fi

  # Cleanup temporary directory if created
  if [ "${cleanup_temp}" == "true" ]; then
    rm -rf "${build_path}"
  fi

  return 0
}

# Build browser image
build_browser_image() {
  local yaml_file="$1"

  local image_name=$(yq eval '.imageName' "${yaml_file}")
  local base_image=$(yq eval '.browser.baseImage' "${yaml_file}")
  local browser=$(yq eval '.browser.browser' "${yaml_file}")
  local dockerfile=$(yq eval '.browser.dockerfile' "${yaml_file}")
  local build_context=$(yq eval '.browser.buildContext' "${yaml_file}")
  local patch_path=$(yq eval '.browser.patchPath // ""' "${yaml_file}")
  local patch_file=$(yq eval '.browser.patchFile // ""' "${yaml_file}")

  print_message "Base: ${base_image}"
  print_message "Browser: ${browser}"

  # Ensure base image exists
  if ! docker image inspect "${base_image}" &>/dev/null; then
    print_error "Base image not found: ${base_image}"
    print_message "Please build ${base_image} first"
    return 1
  fi

  # Tag base image for browser build
  #print_message "Tagging base image..."
  #docker tag "${base_image_name}" "node-${base_image}"

  # If patch specified, create temporary copy of build context
  local actual_build_context="${build_context}"
  local actual_dockerfile="${dockerfile}"
  local cleanup_temp=false

  if [ -n "${patch_path}" ] && [ "${patch_path}" != "null" ] && \
     [ -n "${patch_file}" ] && [ "${patch_file}" != "null" ]; then
    print_message "Creating temporary copy for patching..."
    local temp_dir=$(mktemp -d)
    cp -r "${build_context}/." "${temp_dir}/"
    actual_build_context="${temp_dir}"

    # Dockerfile path needs to be updated if it's in build_context
    if [[ "${dockerfile}" == "${build_context}"* ]]; then
      actual_dockerfile="${temp_dir}/$(basename "${dockerfile}")"
    fi

    cleanup_temp=true

    # Apply patch to temporary copy
    if ! apply_patch_if_specified "${actual_build_context}" "${patch_path}" "${patch_file}"; then
      rm -rf "${temp_dir}"
      return 1
    fi
  fi

  # Build browser image
  print_message "Building browser Docker image..."
  # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
  if ! docker build -f "${actual_dockerfile}" --build-arg BASE_IMAGE="${base_image}" --build-arg BROWSER="${browser}" --build-arg HOST_OS="${HOST_OS}" -t "${image_name}" "${actual_build_context}"; then
    print_error "Docker build failed"
    if [ "${cleanup_temp}" == "true" ]; then
      rm -rf "${actual_build_context}"
    fi
    return 1
  fi

  # Cleanup temporary directory if created
  if [ "${cleanup_temp}" == "true" ]; then
    rm -rf "${actual_build_context}"
  fi

  return 0
}
