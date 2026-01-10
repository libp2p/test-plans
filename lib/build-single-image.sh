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

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib-image-building.sh"
source "${SCRIPT_DIR}/lib-output-formatting.sh"

if [ ! -f "${YAML_FILE}" ]; then
  print_error "Error: YAML file not found: ${YAML_FILE}"
  exit 1
fi

# Load parameters from YAML
imageName=$(yq eval '.imageName' "${YAML_FILE}")
sourceType=$(yq eval '.sourceType' "${YAML_FILE}")
forceRebuild=$(yq eval '.forceRebuild' "${YAML_FILE}")
cacheDir=$(yq eval '.cacheDir' "${YAML_FILE}")
requiresSubmodules=$(yq eval '.requiresSubmodules // false' "${YAML_FILE}")

# Validate required parameters
if [ -z "${imageName}" ] || [ "${imageName}" == "null" ]; then
  print_error "Error: imageName not specified in YAML"
  exit 1
fi

if [ -z "${sourceType}" ] || [ "${sourceType}" == "null" ]; then
  print_error "Error: sourceType not specified in YAML"
  exit 1
fi

# Check if already built (unless force rebuild)
if [ "${forceRebuild}" != "true" ]; then
  if docker image inspect "${imageName}" &>/dev/null; then
    print_success "${imageName} (already built)"
    exit 0
  fi
fi

# Print header
print_header "Building: ${imageName}"
indent
print_message "Type: ${sourceType}"

# Build based on source type
case "${sourceType}" in
  github)
    # Check if submodules are required
    if [ "${requiresSubmodules}" == "true" ]; then
      print_message "Submodules: required"
      build_from_github_with_submodules "${YAML_FILE}" || {
        unindent
        exit 1
      }
    else
      build_from_github "${YAML_FILE}" || {
        unindent
        exit 1
      }
    fi
    ;;
  local)
    build_from_local "${YAML_FILE}" || {
      unindent
      exit 1
    }
    ;;
  browser)
    build_browser_image "${YAML_FILE}" || {
      unindent
      exit 1
    }
    ;;
  *)
    print_error "Error: Unknown source type: ${sourceType}"
    print_message "Valid types: github, local, browser"
    unindent
    exit 1
    ;;
esac

# Show result with image ID (transport style)
IMAGE_ID=$(docker image inspect "${imageName}" -f '{{.Id}}' | cut -d':' -f2)
print_success "Built: ${imageName}"
print_success "Image ID: ${IMAGE_ID}..."
unindent
echo ""

exit 0
