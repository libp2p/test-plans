#!/bin/bash
# Build Docker images for all implementations defined in impls.yaml
# Refactored to use unified YAML-based build system
# Uses content-addressed caching under $CACHE_DIR/snapshots/
# Supports github, local, and browser source types

set -euo pipefail

# Get script directory and change to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."  # Change to transport/ directory

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
FILTER="${1:-}"  # Optional: pipe-separated filter (e.g., "rust-v0.56|rust-v0.55")
REMOVE="${2:-false}"  # Remove the docker image if set (force rebuild)
IMAGE_PREFIX="transport-interop-"
BUILD_SCRIPT="$SCRIPT_DIR/../../scripts/build-single-image.sh"

echo "  → Cache directory: $CACHE_DIR"
if [ -n "$FILTER" ]; then
    echo "  → Filter: $FILTER"
fi

# Ensure cache directories exist
mkdir -p "$CACHE_DIR/snapshots"
mkdir -p "$CACHE_DIR/build-yamls"

# Parse impls.yaml and build each implementation
impl_count=$(yq eval '.implementations | length' impls.yaml)

for ((i=0; i<impl_count; i++)); do
    # Extract implementation details
    impl_id=$(yq eval ".implementations[$i].id" impls.yaml)
    source_type=$(yq eval ".implementations[$i].source.type" impls.yaml)

    # Construct Docker image name with prefix
    image_name="${IMAGE_PREFIX}${impl_id}"

    # Apply filter if specified (substring match on pipe-separated list)
    if [ -n "$FILTER" ]; then
        # Check if impl_id matches any of the pipe-separated filter patterns
        match_found=false
        IFS='|' read -ra FILTER_PATTERNS <<< "$FILTER"
        for pattern in "${FILTER_PATTERNS[@]}"; do
            if [[ "$impl_id" == *"$pattern"* ]]; then
                match_found=true
                break
            fi
        done
        if [ "$match_found" = false ]; then
            continue  # Skip silently
        fi
    fi

    # Check if image already exists
    if docker image inspect "$image_name" &> /dev/null; then
        if [ "$REMOVE" = "true" ]; then
            echo "  → Forcing rebuild of $image_name"
            docker rmi "$image_name" &> /dev/null || echo "Tried to remove non-existent image"
        else
            echo "  ✓ $image_name (already built)"
            continue
        fi
    fi

    # Create YAML file for this build
    yaml_file="$CACHE_DIR/build-yamls/docker-build-${impl_id}.yaml"

    cat > "$yaml_file" <<EOF
imageName: $image_name
imageType: peer
imagePrefix: $IMAGE_PREFIX
sourceType: $source_type
buildLocation: local
cacheDir: $CACHE_DIR
forceRebuild: $REMOVE
outputStyle: clean
EOF

    # Add source-specific parameters
    case "$source_type" in
        github)
            repo=$(yq eval ".implementations[$i].source.repo" impls.yaml)
            commit=$(yq eval ".implementations[$i].source.commit" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)
            build_context=$(yq eval ".implementations[$i].source.buildContext" impls.yaml)
            requires_submodules=$(yq eval ".implementations[$i].source.requiresSubmodules // false" impls.yaml)

            cat >> "$yaml_file" <<EOF

            repo_name=$(basename "$repo")
            echo "→ cloning repo $repo_name"

            # Cache directory for git clones
            git_cache_dir="$CACHE_DIR/git-clones"
            mkdir -p "$git_cache_dir"
            cached_repo_dir="$git_cache_dir/$repo_name-$commit"

            # Check if cached git clone exists and is at correct commit
            if [ -d "$cached_repo_dir" ] && [ -d "$cached_repo_dir/.git" ]; then
                cd "$cached_repo_dir"
                cached_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
                cd - > /dev/null
                if [ "$cached_commit" = "$commit" ]; then
                    echo "  ✓ [HIT] Using cached git clone: $repo_name-$commit"
                    work_dir=$(mktemp -d)
                    trap "rm -rf $work_dir" EXIT
                    extracted_dir="$work_dir/$repo_name-$commit"
                    echo "→ Copying cached repository..."
                    # Copy the repository, preserving submodules (they're already initialized in cache)
                    # Copy everything except .git (Docker builds don't need git history)
                    # This avoids issues with absolute paths in .git/modules
                    mkdir -p "$extracted_dir"
                    rsync -a --exclude='.git' "$cached_repo_dir/" "$extracted_dir/" 2>/dev/null || {
                        # Fallback to cp if rsync not available
                        cp -r "$cached_repo_dir" "$extracted_dir"
                        # Remove .git to avoid path issues (Docker builds don't need it)
                        rm -rf "$extracted_dir/.git"
                    }
                    # Submodules are already present as directories from the cached copy
                    # No need to re-initialize - Docker build only needs the source files
                else
                    echo "  → [MISS] Cached clone at wrong commit, re-cloning..."
                    rm -rf "$cached_repo_dir"
                fi
            fi

            # Clone if not using cached version
            if [ ! -d "$cached_repo_dir" ] || [ ! -d "$cached_repo_dir/.git" ]; then
                echo "  → [MISS] Cloning repository with submodules..."
                work_dir=$(mktemp -d)
                trap "rm -rf $work_dir" EXIT
                extracted_dir="$work_dir/$repo_name-$commit"

                # Clone repository (shallow clone for efficiency, then fetch full history if needed)
                repo_url="https://github.com/$repo.git"
                echo "→ Cloning repository..."
                if ! git clone "$repo_url" "$extracted_dir"; then
                    echo "✗ Failed to clone repository"
                    exit 1
                fi

                # Checkout specific commit
                cd "$extracted_dir"
                echo "→ Checking out commit ${commit:0:8}..."
                if ! git checkout "$commit"; then
                    echo "✗ Failed to checkout commit $commit"
                    exit 1
                fi

                # Check if submodules are required
                if [ "$requires_submodules" = "true" ]; then
                    # Initialize and update submodules for this commit
                    echo "→ Initializing submodules..."
                    if ! git submodule update --init --recursive; then
                        echo "✗ Failed to initialize submodules"
                        exit 1
                    fi
                    cd - > /dev/null
                fi

                # Cache the cloned repository for future use
                echo "→ Caching git clone..."
                mkdir -p "$git_cache_dir"
                cp -r "$extracted_dir" "$cached_repo_dir"
                echo "  ✓ Cached: $repo_name-$commit"
            fi

            # Build Docker image
            echo "→ Building Docker image: docker build -f $extracted_dir/$dockerfile -t $image_name $extracted_dir"
            if ! docker build -f "$extracted_dir/$dockerfile" -t "$image_name" "$extracted_dir"; then
                echo "✗ Docker build failed"
                exit 1
            fi

            # Cleanup extracted snapshot/clone (but keep cached version)
            if [ "$requires_submodules" = "true" ]; then
                # For git clones, always clean up temp work_dir (cached version is separate)
                if [ -n "${work_dir:-}" ] && [ "$work_dir" != "$cached_repo_dir" ]; then
                    echo "→ Cleaning up temporary files..."
                    rm -rf "$work_dir"
                fi
            else
                # For zip downloads, clean up if using temp directory
                if [ "$build_context" != "local" ] && [ -n "${work_dir:-}" ]; then
                    echo "→ Cleaning up temporary files..."
                    rm -rf "$work_dir"
                fi
            fi
            trap - EXIT
            ;;

        local)
            local_path=$(yq eval ".implementations[$i].source.path" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)

            cat >> "$yaml_file" <<EOF

local:
  path: $local_path
  dockerfile: $dockerfile
EOF
            ;;

        browser)
            base_image=$(yq eval ".implementations[$i].source.baseImage" impls.yaml)
            browser=$(yq eval ".implementations[$i].source.browser" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)
            build_context=$(dirname "$dockerfile")

            cat >> "$yaml_file" <<EOF

browser:
  baseImage: $base_image
  browser: $browser
  dockerfile: $dockerfile
  buildContext: $build_context
EOF
            ;;

        *)
            echo "✗ Unknown source type: $source_type"
            exit 1
            ;;
    esac

    # Execute build using unified build system
    bash "$BUILD_SCRIPT" "$yaml_file" || exit 1
done

echo ""
echo "✓ All required images built successfully"
