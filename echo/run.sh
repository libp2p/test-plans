#!/bin/bash

# Echo Protocol Interoperability Tests
# Uses the existing test-plans framework

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source the test-plans library functions
source "${ROOT_DIR}/lib/lib-common-init.sh"
source "${ROOT_DIR}/lib/lib-test-execution.sh"

# Run echo protocol tests using existing framework
exec "${ROOT_DIR}/lib/lib-test-execution.sh" \
  --test-dir "${SCRIPT_DIR}" \
  --images-file "${SCRIPT_DIR}/images.yaml" \
  "$@"