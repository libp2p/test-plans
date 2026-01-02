#!/bin/bash
# Common variable initialization for all test suites
# Provides consistent defaults and variable names across transport, perf, and hole-punch tests

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
#   # etc.
init_common_variables() {
  # Shutdown
  SHUTDOWN=false

  # Files
  IMAGES_YAML=${IMAGES_YAML:-${TEST_ROOT}/images.yaml}

  # Paths
  CACHE_DIR="${CACHE_DIR:-/srv/cache}"
  TEST_RUN_DIR="${TEST_RUN_DIR:-${CACHE_DIR}/test-run}"

  # Common filtering variables
  TEST_IGNORE="${TEST_IGNORE:-}"
  TRANSPORT_IGNORE="${TRANSPORT_IGNORE:-}"
  SECURE_IGNORE="${SECURE_IGNORE:-}"
  MUXER_IGNORE="${MUXER_IGNORE:-}"

  # Execution settings
  WORKER_COUNT="${WORKER_COUNT:-$(nproc 2>/dev/null || echo 4)}"
  DEBUG="${DEBUG:-false}"

  # Common command-line flags
  CHECK_DEPS="${CHECK_DEPS:-false}"
  LIST_IMAGES="${LIST_IMAGES:-false}"
  LIST_TESTS="${LIST_TESTS:-false}"
  CREATE_SNAPSHOT="${CREATE_SNAPSHOT:-false}"
  AUTO_YES="${AUTO_YES:-false}"
  FORCE_MATRIX_REBUILD="${FORCE_MATRIX_REBUILD:-false}"
  FORCE_IMAGE_REBUILD="${FORCE_IMAGE_REBUILD:-false}"

  # Export variables that child scripts and global functions need
  export SHUTDOWN
  export IMAGES_YAML
  export CACHE_DIR
  export TEST_RUN_DIR
  export TEST_IGNORE
  export TRANSPORT_IGNORE
  export SECURE_IGNORE
  export MUXER_IGNORE
  export WORKER_COUNT
  export DEBUG
  export CHECK_DEPS
  export LIST_IMAGES
  export LIST_TESTS
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
