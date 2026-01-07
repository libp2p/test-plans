#!/bin/bash
# Shared image building functions for all test suites
# Used by build-single-image.sh

# Check if Docker image exists
# Usage: docker_image_exists <image_name>
# Returns: 0 if exists, 1 if not
docker_image_exists() {
  local image_name=$1
  docker image inspect "$image_name" >/dev/null 2>&1
}

# Helper function to build images from a YAML section (implementations or baselines)
build_images_from_section() {
  local section="$1"  # "implementations", "baselines", "routers", etc
  local filter="${2:-}" # Optional: pipe-separated filter (e.g., "go-v0.45|rust-v0.56")
  local force_image_rebuild="${3:-false}"

  local count=$(yq eval ".$section | length" "${IMAGES_YAML}")

  for ((i=0; i<count; i++)); do
    local impl_id=$(yq eval ".${section}[$i].id" "${IMAGES_YAML}")
    local source_type=$(yq eval ".${section}[$i].source.type" "${IMAGES_YAML}")

    # Apply filter if specified
    if [ -n "$filter" ]; then
      match_found=false
      IFS='|' read -ra FILTER_PATTERNS <<< "$filter"
      for pattern in "${FILTER_PATTERNS[@]}"; do
        case "$impl_id" in
          *"$pattern"*)
            match_found=true
            break
            ;;
        esac
      done
      if [ "$match_found" == "false" ]; then
        continue
      fi
    fi

    image_name="${TEST_TYPE}-${impl_id}"
    #server_id=$(get_server_config "$impl_id")

    # Determine if remote build
    #if is_remote_server "$server_id"; then
    #  build_location="remote"
    #  hostname=$(get_remote_hostname "$server_id")
    #  username=$(get_remote_username "$server_id")
    #else
      build_location="local"
    #fi

    # Check if image already exists (for local builds only)
    if [ "$build_location" == "local" ]; then
      if [ "$force_image_rebuild" != "true" ] && docker_image_exists "$image_name"; then
        print_success "$image_name (already built)"
        continue
      fi
    fi

    # Create YAML file for this build
    local yaml_file="$CACHE_DIR/build-yamls/docker-build-perf-${impl_id}.yaml"

    cat > "$yaml_file" <<EOF
imageName: $image_name
imageType: peer
imagePrefix: "${TEST_TYPE}"
sourceType: $source_type
buildLocation: $build_location
cacheDir: $CACHE_DIR
forceRebuild: $force_image_rebuild
outputStyle: clean
EOF

# Add remote info if needed
if [ "$build_location" == "remote" ]; then
  cat >> "$yaml_file" <<EOF

remote:
  server: $server_id
  hostname: $hostname
  username: $username
EOF
fi

# Add source-specific parameters
case "$source_type" in
  github)
    local repo=$(yq eval ".${section}[$i].source.repo" "${IMAGES_YAML}")
    local commit=$(yq eval ".${section}[$i].source.commit" "${IMAGES_YAML}")
    local dockerfile=$(yq eval ".${section}[$i].source.dockerfile" "${IMAGES_YAML}")
    local build_context=$(yq eval ".${section}[$i].source.buildContext // \".\"" "${IMAGES_YAML}")
    local requires_submodules=$(yq eval ".${section}[$i].source.requiresSubmodules // false" "${IMAGES_YAML}")

    cat >> "$yaml_file" <<EOF

github:
  repo: $repo
  commit: $commit
  dockerfile: $dockerfile
  buildContext: $build_context

requiresSubmodules: $requires_submodules
EOF
;;

local)
  local local_path=$(yq eval ".${section}[$i].source.path" "${IMAGES_YAML}")
  local dockerfile=$(yq eval ".${section}[$i].source.dockerfile // \"Dockerfile\"" "${IMAGES_YAML}")

  cat >> "$yaml_file" <<EOF

local:
  path: $local_path
  dockerfile: $dockerfile
EOF
;;

browser)
  local base_image=$(yq eval ".${section}[$i].source.baseImage" "${IMAGES_YAML}")
  local browser=$(yq eval ".${section}[$i].source.browser" "${IMAGES_YAML}")
  local dockerfile=$(yq eval ".${section}[$i].source.dockerfile" "${IMAGES_YAML}")
  local build_context=$(dirname "$dockerfile")

  cat >> "$yaml_file" <<EOF

browser:
  baseImage: $base_image
  browser: $browser
  dockerfile: $dockerfile
  buildContext: $build_context
EOF
;;

*)
  print_error "Unknown source type: $source_type"
  exit 1
  ;;
esac

# Execute build (local or remote)
if [ "$build_location" == "remote" ]; then
  # Copy lib-image-building.sh to remote for use by build script
  local lib_script="${SCRIPT_LIB_DIR}/lib-image-building.sh"

  build_on_remote "$yaml_file" "$username" "$hostname" "${SCRIPT_LIB_DIR}/build-single-image.sh" || {
    print_error "Remote build failed for $impl_id"
      exit 1
    }
else
  # Local build
  bash "${SCRIPT_LIB_DIR}/build-single-image.sh" "$yaml_file" || {
    print_error "Local build failed for $impl_id"
      exit 1
    }
fi
done
}

# Download GitHub snapshot to cache
download_github_snapshot() {
  local repo="$1"
  local commit="$2"
  local cache_dir="$3"

  local snapshot_file="$cache_dir/snapshots/$commit.zip"

  if [ ! -f "$snapshot_file" ]; then
    print_error "[MISS] Downloading snapshot..."
    local repo_url="https://github.com/$repo/archive/$commit.zip"
    wget -q -O "$snapshot_file" "$repo_url" || {
      print_error "Failed to download snapshot"
      return 1
    }
    indent
    print_success "Added to cache: $snapshot_file"
    unindent
  else
    print_success "[HIT] Using cached snapshot: $snapshot_file"
  fi

  echo "$snapshot_file"
}

# Extract GitHub snapshot
extract_github_snapshot() {
  local snapshot_file="$1"
  local repo_name="$2"
  local commit="$3"

  local work_dir=$(mktemp -d)
  print_message "Extracting snapshot..."
  unzip -q "$snapshot_file" -d "$work_dir" || {
    print_error "Failed to extract snapshot"
    rm -rf "$work_dir"
    return 1
  }

  local extracted_dir="$work_dir/$repo_name-$commit"
  if [ ! -d "$extracted_dir" ]; then
    print_error "Expected directory not found: $extracted_dir"
    rm -rf "$work_dir"
    return 1
  fi

  echo "$work_dir"  # Caller must clean up with: rm -rf "$work_dir"
}

# Clone GitHub repo with submodules
# Returns path to work directory (caller must clean up)
clone_github_repo_with_submodules() {
  local repo="$1"
  local commit="$2"
  local cache_dir="$3"

  local repo_name=$(basename "$repo")
  local cache_key="${repo_name}-${commit}"
  local cached_clone="$cache_dir/git-repos/$cache_key"

  # Check if already cloned and cached
  if [ -d "$cached_clone" ]; then
    print_success "[HIT] Using cached git clone: ${commit}"

    # Copy to temp directory (avoid modifying cache)
    local work_dir=$(mktemp -d)
    cp -r "$cached_clone" "$work_dir/$repo_name"
    echo "$work_dir"
    return 0
  fi

  print_message "[MISS] Cloning repo with submodules..."

  # Create work directory
  local work_dir=$(mktemp -d)
  local clone_dir="$work_dir/$repo_name"

  # Clone the repository
  print_message "Cloning $repo..."
  if ! git clone --depth 1 "https://github.com/$repo.git" "$clone_dir" 2>&1 | sed 's/^/    /' >&2; then
    print_error "Failed to clone repository"
    rm -rf "$work_dir"
    return 1
  fi

  # Checkout specific commit (need to unshallow for specific commit)
  print_message "Fetching commit ${commit}..."
  cd "$clone_dir"

  # First, try to checkout directly (might already have it from shallow clone)
  if ! git checkout "$commit" 2>/dev/null; then
    # If not, fetch the specific commit
    if ! git fetch --depth 1 origin "$commit" 2>&1 | sed 's/^/    /' >&2; then
      print_error "Failed to fetch commit"
      cd - > /dev/null
      rm -rf "$work_dir"
      return 1
    fi

    if ! git checkout "$commit" 2>&1 | sed 's/^/    /' >&2; then
      print_error "Failed to checkout commit"
      cd - > /dev/null
      rm -rf "$work_dir"
      return 1
    fi
  fi

  # Initialize and update submodules
  print_message "Initializing submodules..."
  if ! git submodule update --init --recursive --depth 1 2>&1 | sed 's/^/    /' >&2; then
    print_error "Failed to initialize submodules"
    cd - > /dev/null
    rm -rf "$work_dir"
    return 1
  fi

  cd - > /dev/null

  # Cache the clone for future use
  print_message "Caching git clone..."
  mkdir -p "$cache_dir/git-repos"
  cp -r "$clone_dir" "$cached_clone"
  print_success "Added to cache: $cached_clone"

  echo "$work_dir"  # Return work_dir (caller must clean up)
}

# Build from GitHub source
build_from_github() {
  local yaml_file="$1"
  local output_filter="$2"

  local image_name=$(yq eval '.imageName' "$yaml_file")
  local repo=$(yq eval '.github.repo' "$yaml_file")
  local commit=$(yq eval '.github.commit' "$yaml_file")
  local dockerfile=$(yq eval '.github.dockerfile' "$yaml_file")
  local build_context=$(yq eval '.github.buildContext' "$yaml_file")
  local cache_dir=$(yq eval '.cacheDir' "$yaml_file")

  print_message "Repo: $repo"
  print_message "Commit: ${commit:0:8}"

  # Download snapshot
  local repo_name=$(basename "$repo")
  local snapshot_file=$(download_github_snapshot "$repo" "$commit" "$cache_dir") || return 1

  # Extract
  local work_dir=$(extract_github_snapshot "$snapshot_file" "$repo_name" "$commit") || return 1
  local extracted_dir="$work_dir/$repo_name-$commit"

  # Determine build context
  local context_dir
  if [ "$build_context" == "." ]; then
    context_dir="$extracted_dir"
  else
    context_dir="$extracted_dir/$build_context"
  fi

  # Build
  print_message "Building Docker image..."

  # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
  if [ "$output_filter" == "cat" ]; then
    if ! docker build -f "$extracted_dir/$dockerfile" -t "$image_name" "$context_dir"; then
      print_error "Docker build failed"
      rm -rf "$work_dir"
      return 1
    fi
  else
    # Use filtering for indented/filtered styles
    if ! eval "docker build -f \"$extracted_dir/$dockerfile\" -t \"$image_name\" \"$context_dir\" 2>&1 | $output_filter"; then
      print_error "Docker build failed"
      rm -rf "$work_dir"
      return 1
    fi
  fi

  rm -rf "$work_dir"
  return 0
}

# Build from GitHub source with submodules support
build_from_github_with_submodules() {
  local yaml_file="$1"
  local output_filter="$2"

  local image_name=$(yq eval '.imageName' "$yaml_file")
  local repo=$(yq eval '.github.repo' "$yaml_file")
  local commit=$(yq eval '.github.commit' "$yaml_file")
  local dockerfile=$(yq eval '.github.dockerfile' "$yaml_file")
  local build_context=$(yq eval '.github.buildContext' "$yaml_file")
  local cache_dir=$(yq eval '.cacheDir' "$yaml_file")

  print_message "Repo: $repo"
  print_message "Commit: ${commit:0:8}"
  print_message "Method: git clone (submodules enabled)"

  # Clone with submodules
  local work_dir=$(clone_github_repo_with_submodules "$repo" "$commit" "$cache_dir") || return 1
  local repo_name=$(basename "$repo")
  local cloned_dir="$work_dir/$repo_name"

  # Determine build context
  local context_dir
  if [ "$build_context" == "." ]; then
    context_dir="$cloned_dir"
  else
    context_dir="$cloned_dir/$build_context"
  fi

  # Build
  print_message "Building Docker image..."

  # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
  if [ "$output_filter" == "cat" ]; then
    if ! docker build -f "$cloned_dir/$dockerfile" -t "$image_name" "$context_dir"; then
      print_error "Docker build failed"
      rm -rf "$work_dir"
      return 1
    fi
  else
    # Use filtering for indented/filtered styles
    if ! eval "docker build -f \"$cloned_dir/$dockerfile\" -t \"$image_name\" \"$context_dir\" 2>&1 | $output_filter"; then
      print_error "Docker build failed"
      rm -rf "$work_dir"
      return 1
    fi
  fi

  rm -rf "$work_dir"
  return 0
}

# Build from local source
build_from_local() {
  local yaml_file="$1"
  local output_filter="$2"

  local image_name=$(yq eval '.imageName' "$yaml_file")
  local local_path=$(yq eval '.local.path' "$yaml_file")
  local dockerfile=$(yq eval '.local.dockerfile' "$yaml_file")

  print_message "Path: $local_path"

  if [ ! -d "$local_path" ]; then
    print_error "Local path not found: $local_path"
    return 1
  fi

  print_message "Building Docker image..."

  # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
  if [ "$output_filter" == "cat" ]; then
    if ! docker build -f "$local_path/$dockerfile" -t "$image_name" "$local_path"; then
      print_error "Docker build failed"
      return 1
    fi
  else
    # Use filtering for indented/filtered styles
    if ! eval "docker build -f \"$local_path/$dockerfile\" -t \"$image_name\" \"$local_path\" 2>&1 | $output_filter"; then
      print_error "Docker build failed"
      return 1
    fi
  fi

  return 0
}

# Build browser image
build_browser_image() {
  local yaml_file="$1"
  local output_filter="$2"

  local image_name=$(yq eval '.imageName' "$yaml_file")
  local base_image=$(yq eval '.browser.baseImage' "$yaml_file")
  local browser=$(yq eval '.browser.browser' "$yaml_file")
  local dockerfile=$(yq eval '.browser.dockerfile' "$yaml_file")
  local build_context=$(yq eval '.browser.buildContext' "$yaml_file")
  local image_prefix=$(yq eval '.imagePrefix' "$yaml_file")

  local base_image_name="${image_prefix}-${base_image}"

  print_message "Base: $base_image ($base_image_name)"
  print_message "Browser: $browser"

  # Ensure base image exists
  if ! docker image inspect "$base_image_name" &>/dev/null; then
    print_error "Base image not found: $base_image_name"
    print_message "Please build $base_image first"
    return 1
  fi

  # Tag base image for browser build
  print_message "Tagging base image..."
  docker tag "$base_image_name" "node-$base_image"

  # Build browser image
  print_message "Building browser Docker image..."

  # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
  if [ "$output_filter" == "cat" ]; then
    if ! docker build -f "$dockerfile" --build-arg BASE_IMAGE="node-$base_image" --build-arg BROWSER="$browser" -t "$image_name" "$build_context"; then
      print_error "Docker build failed"
      return 1
    fi
  else
    # Use filtering for indented/filtered styles
    if ! eval "docker build -f \"$dockerfile\" --build-arg BASE_IMAGE=\"node-$base_image\" --build-arg BROWSER=\"$browser\" -t \"$image_name\" \"$build_context\" 2>&1 | $output_filter"; then
      print_error "Docker build failed"
      return 1
    fi
  fi

  return 0
}

# Get output filter command based on style
get_output_filter() {
  local style="$1"

  case "$style" in
    indented)
      echo "sed 's/^/    /'"
      ;;
    filtered)
      echo "grep -E '^(#|Step|Successfully|ERROR)'"
      ;;
    clean|*)
      echo "cat"
      ;;
  esac
}
