#!/usr/bin/env bash
# Common variable initialization for all test suites
# Provides consistent defaults and variable names across transport, perf, and hole-punch tests

# Source lib-host-os.sh if not already loaded
if ! type detect_host_os &>/dev/null; then
  _common_init_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_common_init_script_dir}/lib-host-os.sh"
fi

# Initialize common variables with standard defaults
# This function should be called early in all run.sh scripts, after SCRIPT_LIB_DIR is set
# but before test-specific variable definitions
#
# Usage:
#   source "$SCRIPT_LIB_DIR/lib-common-init.sh"
#   init_common_variables
#
#   # Then override or define test-specific variables:
#   # For perf:
#   WORKER_COUNT=1  # Perf must run sequentially (1 test at a time)
#   BASELINE_SELECT="${BASELINE_SELECT:-}"
#   BASELINE_IGNORE="${BASELINE_IGNORE:-}"
#   # For hole-punch:
#   RELAY_SELECT="${RELAY_SELECT:-}"
#   RELAY_IGNORE="${RELAY_IGNORE:-}"
#   ROUTER_SELECT="${ROUTER_SELECT:-}"
#   ROUTER_IGNORE="${ROUTER_IGNORE:-}"
#   # etc.
init_common_variables() {
  # Shutdown
  SHUTDOWN=false

  # Host operating system detection
  # Detect or use existing HOST_OS value (may be loaded from inputs.yaml)
  HOST_OS="${HOST_OS:-$(detect_host_os)}"

  # Files
  IMAGES_YAML="${IMAGES_YAML:-${TEST_ROOT}/images.yaml}"

  # Paths
  CACHE_DIR="${CACHE_DIR:-${TEST_ROOT}/.cache}"
  TEST_RUN_DIR="${TEST_RUN_DIR:-${CACHE_DIR}/test-run}"

  # Common filtering variables (dimension-based)
  IMPL_SELECT="${IMPL_SELECT:-}"           # Implementation select filter
  IMPL_IGNORE="${IMPL_IGNORE:-}"           # Implementation ignore filter (renamed from TEST_IGNORE)
  TRANSPORT_SELECT="${TRANSPORT_SELECT:-}" # Transport select filter
  TRANSPORT_IGNORE="${TRANSPORT_IGNORE:-}" # Transport ignore filter
  SECURE_SELECT="${SECURE_SELECT:-}"       # Secure channel select filter
  SECURE_IGNORE="${SECURE_IGNORE:-}"       # Secure channel ignore filter
  MUXER_SELECT="${MUXER_SELECT:-}"         # Muxer select filter
  MUXER_IGNORE="${MUXER_IGNORE:-}"         # Muxer ignore filter
  TEST_SELECT="${TEST_SELECT:-}"           # Test name select filter (NEW)
  TEST_IGNORE="${TEST_IGNORE:-}"           # Test name ignore filter (NEW)

  # Execution settings
  WORKER_COUNT="${WORKER_COUNT:-$(get_cpu_count)}"
  DEBUG="${DEBUG:-false}"

  # Common command-line flags
  CHECK_DEPS="${CHECK_DEPS:-false}"
  LIST_IMAGES="${LIST_IMAGES:-false}"
  LIST_TESTS="${LIST_TESTS:-false}"
  SHOW_IGNORED="${SHOW_IGNORED:-false}"
  CREATE_SNAPSHOT="${CREATE_SNAPSHOT:-false}"
  AUTO_YES="${AUTO_YES:-false}"
  FORCE_MATRIX_REBUILD="${FORCE_MATRIX_REBUILD:-false}"
  FORCE_IMAGE_REBUILD="${FORCE_IMAGE_REBUILD:-false}"

  # Export variables that child scripts and global functions need
  export SHUTDOWN
  export HOST_OS
  export IMAGES_YAML
  export CACHE_DIR
  export TEST_RUN_DIR
  # Export filter variables (dimension-based)
  export IMPL_SELECT IMPL_IGNORE
  export TRANSPORT_SELECT TRANSPORT_IGNORE
  export SECURE_SELECT SECURE_IGNORE
  export MUXER_SELECT MUXER_IGNORE
  export TEST_SELECT TEST_IGNORE
  export WORKER_COUNT
  export DEBUG
  export CHECK_DEPS
  export LIST_IMAGES
  export LIST_TESTS
  export SHOW_IGNORED
  export CREATE_SNAPSHOT
  export AUTO_YES
  export FORCE_MATRIX_REBUILD
  export FORCE_IMAGE_REBUILD
}

# Initialize caching directories
# This function should be called early in all run.sh scripts, after
# init_common_variables is run.
#
# Usage:
#   source "$SCRIPT_LIB_DIR/lib-common-init.sh"
#   init_cache_dirs
#
init_cache_dirs() {
  mkdir -p "${CACHE_DIR}/snapshots"
  mkdir -p "${CACHE_DIR}/build-yamls"
  mkdir -p "${CACHE_DIR}/test-run"
  mkdir -p "${CACHE_DIR}/test-run-matrix"
}

# Can be hooked up to handle ctrl+c
handle_shutdown() {
  SHUTDOWN=true
}
