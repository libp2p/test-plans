#!/bin/bash
# Shared image building functions for all test suites
# Used by build-single-image.sh

# Download GitHub snapshot to cache
download_github_snapshot() {
    local repo="$1"
    local commit="$2"
    local cache_dir="$3"

    local snapshot_file="$cache_dir/snapshots/$commit.zip"

    if [ ! -f "$snapshot_file" ]; then
        echo "  → [MISS] Downloading snapshot..." >&2
        local repo_url="https://github.com/$repo/archive/$commit.zip"
        wget -q -O "$snapshot_file" "$repo_url" || {
            echo "✗ Failed to download snapshot" >&2
            return 1
        }
        echo "  ✓ Added to cache: ${commit:0:8}.zip" >&2
    else
        echo "  ✓ [HIT] Using cached snapshot: ${commit:0:8}.zip" >&2
    fi

    echo "$snapshot_file"
}

# Extract GitHub snapshot
extract_github_snapshot() {
    local snapshot_file="$1"
    local repo_name="$2"
    local commit="$3"

    local work_dir=$(mktemp -d)
    echo "→ Extracting snapshot..." >&2
    unzip -q "$snapshot_file" -d "$work_dir" || {
        echo "✗ Failed to extract snapshot" >&2
        rm -rf "$work_dir"
        return 1
    }

    local extracted_dir="$work_dir/$repo_name-$commit"
    if [ ! -d "$extracted_dir" ]; then
        echo "✗ Expected directory not found: $extracted_dir" >&2
        rm -rf "$work_dir"
        return 1
    fi

    echo "$work_dir"  # Caller must clean up with: rm -rf "$work_dir"
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

    echo "→ Repo: $repo"
    echo "→ Commit: ${commit:0:8}"

    # Download snapshot
    local repo_name=$(basename "$repo")
    local snapshot_file=$(download_github_snapshot "$repo" "$commit" "$cache_dir") || return 1

    # Extract
    local work_dir=$(extract_github_snapshot "$snapshot_file" "$repo_name" "$commit") || return 1
    local extracted_dir="$work_dir/$repo_name-$commit"

    # Determine build context
    local context_dir
    if [ "$build_context" = "." ]; then
        context_dir="$extracted_dir"
    else
        context_dir="$extracted_dir/$build_context"
    fi

    # Build
    echo "→ Building Docker image..."

    # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
    if [ "$output_filter" = "cat" ]; then
        if ! docker build -f "$extracted_dir/$dockerfile" -t "$image_name" "$context_dir"; then
            echo "✗ Docker build failed"
            rm -rf "$work_dir"
            return 1
        fi
    else
        # Use filtering for indented/filtered styles
        if ! eval "docker build -f \"$extracted_dir/$dockerfile\" -t \"$image_name\" \"$context_dir\" 2>&1 | $output_filter"; then
            echo "✗ Docker build failed"
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

    echo "→ Path: $local_path"

    if [ ! -d "$local_path" ]; then
        echo "✗ Local path not found: $local_path"
        return 1
    fi

    echo "→ Building Docker image..."

    # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
    if [ "$output_filter" = "cat" ]; then
        if ! docker build -f "$local_path/$dockerfile" -t "$image_name" "$local_path"; then
            echo "✗ Docker build failed"
            return 1
        fi
    else
        # Use filtering for indented/filtered styles
        if ! eval "docker build -f \"$local_path/$dockerfile\" -t \"$image_name\" \"$local_path\" 2>&1 | $output_filter"; then
            echo "✗ Docker build failed"
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

    local base_image_name="${image_prefix}${base_image}"

    echo "→ Base: $base_image ($base_image_name)"
    echo "→ Browser: $browser"

    # Ensure base image exists
    if ! docker image inspect "$base_image_name" &>/dev/null; then
        echo "✗ Base image not found: $base_image_name"
        echo "  Please build $base_image first"
        return 1
    fi

    # Tag base image for browser build
    echo "→ Tagging base image..."
    docker tag "$base_image_name" "node-$base_image"

    # Build browser image
    echo "→ Building browser Docker image..."

    # Run docker directly (no eval/pipe) for clean output to preserve aesthetic
    if [ "$output_filter" = "cat" ]; then
        if ! docker build -f "$dockerfile" --build-arg BASE_IMAGE="node-$base_image" --build-arg BROWSER="$browser" -t "$image_name" "$build_context"; then
            echo "✗ Docker build failed"
            return 1
        fi
    else
        # Use filtering for indented/filtered styles
        if ! eval "docker build -f \"$dockerfile\" --build-arg BASE_IMAGE=\"node-$base_image\" --build-arg BROWSER=\"$browser\" -t \"$image_name\" \"$build_context\" 2>&1 | $output_filter"; then
            echo "✗ Docker build failed"
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
