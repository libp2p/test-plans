#!/bin/bash
# Build Docker images for perf implementations
# Refactored to use unified YAML-based build system
# Supports local and remote builds

set -euo pipefail

# Get script directory and change to perf directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Source required libraries
source "$SCRIPT_LIB_DIR/lib-image-naming.sh"
source "$SCRIPT_LIB_DIR/lib-remote-execution.sh"
source "lib/lib-perf.sh"

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
FILTER="${1:-}"  # Optional: pipe-separated filter (e.g., "go-v0.45|rust-v0.56")
FORCE_IMAGE_REBUILD="${2:-false}"
IMAGE_PREFIX="perf-"
BUILD_SCRIPT="$SCRIPT_LIB_DIR/build-single-image.sh"

echo "  → Cache directory: $CACHE_DIR"
if [ -n "$FILTER" ]; then
    echo "  → Filter: $FILTER"
fi
echo ""

# Ensure cache directories exist
mkdir -p "$CACHE_DIR/snapshots"
mkdir -p "$CACHE_DIR/build-yamls"

# Helper function to build images from a YAML section (implementations or baselines)
build_images_from_section() {
    local section="$1"  # "implementations" or "baselines"
    local count=$(yq eval ".$section | length" images.yaml)

    for ((i=0; i<count; i++)); do
        local impl_id=$(yq eval ".${section}[$i].id" images.yaml)
        local source_type=$(yq eval ".${section}[$i].source.type" images.yaml)

        # Apply filter if specified
        if [ -n "$FILTER" ]; then
            match_found=false
            IFS='|' read -ra FILTER_PATTERNS <<< "$FILTER"
            for pattern in "${FILTER_PATTERNS[@]}"; do
                if [[ "$impl_id" == *"$pattern"* ]]; then
                    match_found=true
                    break
                fi
            done
            if [ "$match_found" = false ]; then
                continue
            fi
        fi

        image_name="${IMAGE_PREFIX}${impl_id}"
        server_id=$(get_server_config "$impl_id")

        # Determine if remote build
        if is_remote_server "$server_id"; then
            build_location="remote"
            hostname=$(get_remote_hostname "$server_id")
            username=$(get_remote_username "$server_id")
        else
            build_location="local"
        fi

        # Check if image already exists (for local builds only)
        if [ "$build_location" = "local" ]; then
            if [ "$FORCE_IMAGE_REBUILD" != "true" ] && docker_image_exists "$image_name"; then
                echo "  ✓ $image_name (already built)"
                continue
            fi
        fi

        # Create YAML file for this build
        local yaml_file="$CACHE_DIR/build-yamls/docker-build-perf-${impl_id}.yaml"

        cat > "$yaml_file" <<EOF
imageName: $image_name
imageType: peer
imagePrefix: $IMAGE_PREFIX
sourceType: $source_type
buildLocation: $build_location
cacheDir: $CACHE_DIR
forceRebuild: $FORCE_IMAGE_REBUILD
outputStyle: clean
EOF

        # Add remote info if needed
        if [ "$build_location" = "remote" ]; then
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
                local repo=$(yq eval ".${section}[$i].source.repo" images.yaml)
                local commit=$(yq eval ".${section}[$i].source.commit" images.yaml)
                local dockerfile=$(yq eval ".${section}[$i].source.dockerfile" images.yaml)
                local build_context=$(yq eval ".${section}[$i].source.buildContext // \".\"" images.yaml)
                local requires_submodules=$(yq eval ".${section}[$i].source.requiresSubmodules // false" images.yaml)

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
                local local_path=$(yq eval ".${section}[$i].source.path" images.yaml)
                local dockerfile=$(yq eval ".${section}[$i].source.dockerfile // \"Dockerfile\"" images.yaml)

                cat >> "$yaml_file" <<EOF

local:
  path: $local_path
  dockerfile: $dockerfile
EOF
                ;;

            browser)
                local base_image=$(yq eval ".${section}[$i].source.baseImage" images.yaml)
                local browser=$(yq eval ".${section}[$i].source.browser" images.yaml)
                local dockerfile=$(yq eval ".${section}[$i].source.dockerfile" images.yaml)
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
                echo "✗ Unknown source type: $source_type"
                exit 1
                ;;
        esac

        # Execute build (local or remote)
        if [ "$build_location" = "remote" ]; then
            # Copy lib-image-building.sh to remote for use by build script
            local lib_script="$SCRIPT_LIB_DIR/lib-image-building.sh"

            build_on_remote "$yaml_file" "$username" "$hostname" "$BUILD_SCRIPT" || {
                echo "✗ Remote build failed for $impl_id"
                exit 1
            }
        else
            # Local build
            bash "$BUILD_SCRIPT" "$yaml_file" || {
                echo "✗ Local build failed for $impl_id"
                exit 1
            }
        fi
    done
}

# Build images from both baselines and implementations
build_images_from_section "baselines"
build_images_from_section "implementations"

echo ""
echo "  ✓ All images built successfully"
echo ""
