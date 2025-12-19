#!/bin/bash
# Build Docker images for all hole-punch components (relays, routers, peers)
# Refactored to use unified YAML-based build system
# Uses content-addressed caching under $CACHE_DIR/snapshots/

set -euo pipefail

# Get script directory and change to hole-punch directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
RELAY_FILTER="${1:-}"      # Optional: pipe-separated relay ID filter
ROUTER_FILTER="${2:-}"     # Optional: pipe-separated router ID filter
IMPL_FILTER="${3:-}"       # Optional: pipe-separated implementation ID filter
FORCE_REBUILD="${4:-false}"  # Optional: force rebuild all images
BUILD_SCRIPT="$SCRIPT_DIR/../../lib/build-single-image.sh"

echo "  → Cache directory: $CACHE_DIR"
[ -n "$RELAY_FILTER" ] && echo "  → Relay filter: $RELAY_FILTER"
[ -n "$ROUTER_FILTER" ] && echo "  → Router filter: $ROUTER_FILTER"
[ -n "$IMPL_FILTER" ] && echo "  → Implementation filter: $IMPL_FILTER"
[ "$FORCE_REBUILD" = "true" ] && echo "  → Force rebuild: enabled"
echo ""

# Ensure cache directories exist
mkdir -p "$CACHE_DIR/snapshots"
mkdir -p "$CACHE_DIR/build-yamls"

# Helper function to build any image type (relay/router/peer)
# This unifies the build process - all three types use the same logic!
build_image_type() {
    local image_type="$1"        # relay, router, or peer
    local yaml_section="$2"      # relays, routers, or implementations
    local filter="$3"
    local prefix="hole-punch-${image_type}-"

    local count=$(yq eval ".$yaml_section | length" images.yaml)

    for ((i=0; i<count; i++)); do
        local id=$(yq eval ".${yaml_section}[$i].id" images.yaml)

        # Apply filter if specified
        if [ -n "$filter" ]; then
            match_found=false
            IFS='|' read -ra FILTER_PATTERNS <<< "$filter"
            for pattern in "${FILTER_PATTERNS[@]}"; do
                if [[ "$id" == *"$pattern"* ]]; then
                    match_found=true
                    break
                fi
            done
            if [ "$match_found" = false ]; then
                continue
            fi
        fi

        local image_name="${prefix}${id}"
        local source_type=$(yq eval ".${yaml_section}[$i].source.type" images.yaml)

        # Check if image already exists (skip if not forcing rebuild)
        if [ "$FORCE_REBUILD" = "false" ] && docker image inspect "$image_name" &>/dev/null; then
            echo "  ✓ $image_name (already built)"
            continue
        fi

        # Create YAML file for this build
        local yaml_file="$CACHE_DIR/build-yamls/docker-build-${image_type}-${id}.yaml"

        cat > "$yaml_file" <<EOF
imageName: $image_name
imageType: $image_type
imagePrefix: $prefix
sourceType: $source_type
buildLocation: local
cacheDir: $CACHE_DIR
forceRebuild: $FORCE_REBUILD
outputStyle: clean
EOF

        # Add source-specific parameters
        case "$source_type" in
            github)
                local repo=$(yq eval ".${yaml_section}[$i].source.repo" images.yaml)
                local commit=$(yq eval ".${yaml_section}[$i].source.commit" images.yaml)
                local dockerfile=$(yq eval ".${yaml_section}[$i].source.dockerfile" images.yaml)
                local build_context=$(yq eval ".${yaml_section}[$i].source.buildContext // \".\"" images.yaml)
                local requires_submodules=$(yq eval ".${yaml_section}[$i].source.requiresSubmodules // false" images.yaml)

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
                local local_path=$(yq eval ".${yaml_section}[$i].source.path" images.yaml)
                local dockerfile=$(yq eval ".${yaml_section}[$i].source.dockerfile" images.yaml)

                cat >> "$yaml_file" <<EOF

local:
  path: $local_path
  dockerfile: $dockerfile
EOF
                ;;

            browser)
                local base_image=$(yq eval ".${yaml_section}[$i].source.baseImage" images.yaml)
                local browser=$(yq eval ".${yaml_section}[$i].source.browser" images.yaml)
                local dockerfile=$(yq eval ".${yaml_section}[$i].source.dockerfile" images.yaml)
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

        # Execute build using unified build system
        bash "$BUILD_SCRIPT" "$yaml_file" || {
            echo "✗ Build failed for ${image_type}: $id"
            exit 1
        }
    done
}

# Build all image types using the same unified process
build_image_type "relay" "relays" "$RELAY_FILTER"
build_image_type "router" "routers" "$ROUTER_FILTER"
build_image_type "peer" "implementations" "$IMPL_FILTER"

echo ""
echo "✓ All required images built successfully"
