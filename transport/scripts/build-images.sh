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
            build_context=$(yq eval ".implementations[$i].source.buildContext // \".\"" impls.yaml)

            cat >> "$yaml_file" <<EOF

github:
  repo: $repo
  commit: $commit
  dockerfile: $dockerfile
  buildContext: $build_context
EOF
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
