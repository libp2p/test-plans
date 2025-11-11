#!/bin/bash
# Build Docker images for all implementations defined in impls.yaml
# Uses content-addressed caching under $CACHE_DIR/snapshots/
# Supports github, local, and browser source types

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
FILTER="${1:-}"  # Optional: pipe-separated filter (e.g., "rust-v0.56|rust-v0.55")

echo "Building Docker images..."
echo "Cache directory: $CACHE_DIR"
if [ -n "$FILTER" ]; then
    echo "Filter: $FILTER"
fi
echo ""

# Ensure cache directory exists
mkdir -p "$CACHE_DIR/snapshots"

# Parse impls.yaml and build each implementation
impl_count=$(yq eval '.implementations | length' impls.yaml)

for ((i=0; i<impl_count; i++)); do
    # Extract implementation details
    impl_id=$(yq eval ".implementations[$i].id" impls.yaml)
    source_type=$(yq eval ".implementations[$i].source.type" impls.yaml)

    # Apply filter if specified (exact match only, not substring)
    if [ -n "$FILTER" ] && [[ ! "$impl_id" =~ ^($FILTER)$ ]]; then
        continue  # Skip silently
    fi

    # Check if image already exists
    if docker image inspect "$impl_id" &> /dev/null; then
        echo "  ✓ $impl_id (already built)"
        continue
    fi

    echo ""
    echo "╲ Building: $impl_id"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "  Type: $source_type"

    case "$source_type" in
        github)
            # GitHub source type
            repo=$(yq eval ".implementations[$i].source.repo" impls.yaml)
            commit=$(yq eval ".implementations[$i].source.commit" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)
            build_context=$(yq eval ".implementations[$i].source.buildContext" impls.yaml)

            echo "  Repo: $repo"
            echo "  Commit: ${commit:0:8}"

            # Download snapshot if not cached
            snapshot_file="$CACHE_DIR/snapshots/$commit.zip"
            if [ ! -f "$snapshot_file" ]; then
                echo "→ Downloading snapshot..."
                repo_url="https://github.com/$repo/archive/$commit.zip"
                wget -O "$snapshot_file" "$repo_url" || {
                    echo "✗ Failed to download snapshot"
                    exit 1
                }
                echo "  ✓ Added to cache: ${commit:0:8}.zip"
            else
                echo "→ Using cached snapshot: ${commit:0:8}.zip"
            fi

            # Check if using local build context
            if [ "$build_context" = "local" ]; then
                work_dir="impls/${impl_id//-//}"  # Convert python-v0.4 to impls/python/v0.4
                if [ ! -d "$work_dir" ]; then
                    echo "✗ Working dir not found: $work_dir"
                    exit 1
                fi

            else
                # Extract snapshot to temporary directory
                work_dir=$(mktemp -d)
                trap "rm -rf $work_dir" EXIT
            fi

            # Find extracted directory (GitHub archives are named repo-commit)
            repo_name=$(basename "$repo")
            extracted_dir="$work_dir/$repo_name-$commit"

            # Remove old extracted snapshot if it exists
            rm -rf "$work_dir/$repo_name-"*

            echo "→ Extracting snapshot to: ${work_dir}"
            unzip -q "$snapshot_file" -d "$work_dir"

            if [ ! -d "$extracted_dir" ]; then
                echo "✗ Expected directory not found: $extracted_dir"
                exit 1
            fi

            # Build Docker image
            echo "→ Building Docker image..."
            if ! docker build -f "$extracted_dir/$dockerfile" -t "$impl_id" "$extracted_dir"; then
                echo "✗ Docker build failed"
                exit 1
            fi

            # Cleanup extracted snapshot
            echo "→ Cleaning up extracted snapshot..."
            rm -rf "$work_dir/$extracted_dir"
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
            if ! docker build -f "$local_path/$dockerfile" -t "$impl_id" "$local_path"; then
                echo "✗ Docker build failed"
                exit 1
            fi
            ;;

        browser)
            # Browser source type
            base_image=$(yq eval ".implementations[$i].source.baseImage" impls.yaml)
            browser=$(yq eval ".implementations[$i].source.browser" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)

            echo "  Base: $base_image"
            echo "  Browser: $browser"

            # Ensure base image exists
            if ! docker image inspect "$base_image" &> /dev/null; then
                echo "✗ Base image not found: $base_image"
                echo "  Please build $base_image first"
                exit 1
            fi

            # Tag base image for browser build
            echo "→ Tagging base image..."
            docker tag "$base_image" "node-$base_image"

            # Build browser image
            echo "→ Building browser Docker image..."
            dockerfile_dir=$(dirname "$dockerfile")
            if ! docker build \
                -f "$dockerfile" \
                --build-arg BASE_IMAGE="node-$base_image" \
                --build-arg BROWSER="$browser" \
                -t "$impl_id" \
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
    image_id=$(docker image inspect "$impl_id" -f '{{.Id}}' | cut -d':' -f2)
    echo "  ✓ Built: $impl_id"
    echo "  ✓ Image ID: ${image_id:0:12}..."
done

echo ""
echo "✓ All required images built successfully"
echo ""
