#!/bin/bash
# Build Docker images for all implementations defined in impls.yaml
# Uses content-addressed caching under $CACHE_DIR/snapshots/
# Supports github, local, and browser source types

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
FILTER="${1:-}"  # Optional: pipe-separated filter (e.g., "rust-v0.56|rust-v0.55")
REMOVE="${2:-false}"  # Remove the docker image if set

echo "  → Cache directory: $CACHE_DIR"
if [ -n "$FILTER" ]; then
    echo "  → Filter: $FILTER"
fi

# Ensure cache directory exists
mkdir -p "$CACHE_DIR/snapshots"

# Parse impls.yaml and build each implementation
impl_count=$(yq eval '.implementations | length' impls.yaml)

for ((i=0; i<impl_count; i++)); do
    # Extract implementation details
    impl_id=$(yq eval ".implementations[$i].id" impls.yaml)
    source_type=$(yq eval ".implementations[$i].source.type" impls.yaml)

    # Construct Docker image name with prefix
    image_name="transport-interop-${impl_id}"

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

    echo ""
    echo "╲ Building: $impl_id ($image_name)"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "→ Type: $source_type"

    case "$source_type" in
        github)
            # GitHub source type
            repo=$(yq eval ".implementations[$i].source.repo" impls.yaml)
            commit=$(yq eval ".implementations[$i].source.commit" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)
            build_context=$(yq eval ".implementations[$i].source.buildContext" impls.yaml)
            requires_submodules=$(yq eval ".implementations[$i].source.requiresSubmodules // false" impls.yaml)

            echo "→ Repo: $repo"
            echo "→ Commit: ${commit:0:8}"

            repo_name=$(basename "$repo")

            # Check if submodules are required
            if [ "$requires_submodules" = "true" ]; then
                echo "→ Submodules required: using git clone"

                # Use git clone for repositories with submodules
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
                        # Copy the repository, preserving submodules
                        cp -r "$cached_repo_dir" "$extracted_dir"
                        # Ensure submodules are properly initialized in the copied location
                        cd "$extracted_dir"
                        if [ -f .gitmodules ]; then
                            git submodule update --init --recursive 2>/dev/null || true
                        fi
                        cd - > /dev/null
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

                    # Initialize and update submodules for this commit
                    echo "→ Initializing submodules..."
                    if ! git submodule update --init --recursive; then
                        echo "✗ Failed to initialize submodules"
                        exit 1
                    fi
                    cd - > /dev/null

                    # Cache the cloned repository for future use
                    echo "→ Caching git clone..."
                    mkdir -p "$git_cache_dir"
                    cp -r "$extracted_dir" "$cached_repo_dir"
                    echo "  ✓ Cached: $repo_name-$commit"
                fi
            else
                # Use zip download for repositories without submodules
                # Download snapshot if not cached
                snapshot_file="$CACHE_DIR/snapshots/$commit.zip"
                if [ ! -f "$snapshot_file" ]; then
                    echo "  → [MISS] Downloading snapshot..."
                    repo_url="https://github.com/$repo/archive/$commit.zip"
                    wget -O "$snapshot_file" "$repo_url" || {
                        echo "✗ Failed to download snapshot"
                        exit 1
                    }
                    echo "  ✓ Added to cache: ${commit:0:8}.zip"
                else
                    echo "  ✓ [HIT] Using cached snapshot: ${commit:0:8}.zip"
                fi

                # Check if using local build context
                if [ "$build_context" = "local" ]; then
                    work_dir="impls/${impl_id//-//}"  # Convert python-v0.4 to impls/python/v0.4

                    if [ ! -d "$work_dir" ]; then
                        echo "✗ Working dir not found: $work_dir"
                        exit 1
                    fi

                    # Remove old extracted snapshot if it exists
                    rm -rf "$work_dir/$repo_name-"*

                    extracted_dir="$work_dir"
                else
                    # Extract snapshot to temporary directory
                    work_dir=$(mktemp -d)
                    trap "rm -rf $work_dir" EXIT
                    extracted_dir="$work_dir/$repo_name-$commit"
                fi

                echo "→ Extracting snapshot to: ${work_dir}"
                unzip -q "$snapshot_file" -d "$work_dir"

                if [ ! -d "$work_dir/$repo_name-$commit" ]; then
                    echo "✗ Expected directory not found: $work_dir/$repo_name-$commit"
                    exit 1
                fi
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
            # Local source type
            local_path=$(yq eval ".implementations[$i].source.path" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)

            echo "  Path: $local_path"

            if [ ! -d "$local_path" ]; then
                echo "✗ Local path not found: $local_path"
                exit 1
            fi

            echo "→ Building Docker image from local source..."
            if ! docker build -f "$local_path/$dockerfile" -t "$image_name" "$local_path"; then
                echo "✗ Docker build failed"
                exit 1
            fi
            ;;

        browser)
            # Browser source type
            base_image=$(yq eval ".implementations[$i].source.baseImage" impls.yaml)
            browser=$(yq eval ".implementations[$i].source.browser" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)

            # Construct base image name with prefix
            base_image_name="transport-interop-${base_image}"

            echo "  Base: $base_image ($base_image_name)"
            echo "  Browser: $browser"

            # Ensure base image exists
            if ! docker image inspect "$base_image_name" &> /dev/null; then
                echo "✗ Base image not found: $base_image_name"
                echo "  Please build $base_image first"
                exit 1
            fi

            # Tag base image for browser build
            echo "→ Tagging base image..."
            docker tag "$base_image_name" "node-$base_image"

            # Build browser image
            echo "→ Building browser Docker image..."
            dockerfile_dir=$(dirname "$dockerfile")
            if ! docker build \
                -f "$dockerfile" \
                --build-arg BASE_IMAGE="node-$base_image" \
                --build-arg BROWSER="$browser" \
                -t "$image_name" \
                "$dockerfile_dir"; then
                echo "✗ Docker build failed"
                exit 1
            fi
            ;;

        *)
            echo "✗ Unknown source type: $source_type"
            exit 1
            ;;
    esac

    # Get image ID
    image_id=$(docker image inspect "$image_name" -f '{{.Id}}' | cut -d':' -f2)
    echo "✓ Built: $image_name"
    echo "✓ Image ID: ${image_id:0:12}..."
done

echo ""
echo "✓ All required images built successfully"
