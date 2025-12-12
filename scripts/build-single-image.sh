#!/bin/bash
# Thin executor: Builds a single Docker image based on YAML parameters
# Used by all test suites (transport, perf, hole-punch)

set -euo pipefail

# Validate arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <path-to-yaml-file>"
    echo ""
    echo "Example:"
    echo "  $0 /srv/cache/build-yamls/docker-build-rust-v0.56.yaml"
    exit 1
fi

YAML_FILE="$1"

if [ ! -f "$YAML_FILE" ]; then
    echo "✗ Error: YAML file not found: $YAML_FILE"
    exit 1
fi

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-image-building.sh"

# Load parameters from YAML
imageName=$(yq eval '.imageName' "$YAML_FILE")
sourceType=$(yq eval '.sourceType' "$YAML_FILE")
forceRebuild=$(yq eval '.forceRebuild' "$YAML_FILE")
outputStyle=$(yq eval '.outputStyle' "$YAML_FILE")
cacheDir=$(yq eval '.cacheDir' "$YAML_FILE")

# Validate required parameters
if [ -z "$imageName" ] || [ "$imageName" = "null" ]; then
    echo "✗ Error: imageName not specified in YAML"
    exit 1
fi

if [ -z "$sourceType" ] || [ "$sourceType" = "null" ]; then
    echo "✗ Error: sourceType not specified in YAML"
    exit 1
fi

# Check if already built (unless force rebuild)
if [ "$forceRebuild" != "true" ]; then
    if docker image inspect "$imageName" &>/dev/null; then
        echo "  ✓ $imageName (already built)"
        exit 0
    fi
fi

# Print header
echo ""
echo "╲ Building: $imageName"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ Type: $sourceType"

# Get output filter
OUTPUT_FILTER=$(get_output_filter "$outputStyle")

# Build based on source type
case "$sourceType" in
    github)
        build_from_github "$YAML_FILE" "$OUTPUT_FILTER" || exit 1
        ;;
    local)
        build_from_local "$YAML_FILE" "$OUTPUT_FILTER" || exit 1
        ;;
    browser)
        build_browser_image "$YAML_FILE" "$OUTPUT_FILTER" || exit 1
        ;;
    *)
        echo "✗ Error: Unknown source type: $sourceType"
        echo "  Valid types: github, local, browser"
        exit 1
        ;;
esac

# Show result with image ID (transport style)
image_id=$(docker image inspect "$imageName" -f '{{.Id}}' | cut -d':' -f2)
echo "✓ Built: $imageName"
echo "✓ Image ID: ${image_id:0:12}..."
echo ""

exit 0
