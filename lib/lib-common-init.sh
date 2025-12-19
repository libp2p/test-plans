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
    # Paths
    CACHE_DIR="${CACHE_DIR:-/srv/cache}"
    TEST_RUN_DIR="${TEST_RUN_DIR:-$CACHE_DIR/test-run}"

    # Common filtering variables
    TEST_SELECT="${TEST_SELECT:-}"
    TEST_IGNORE="${TEST_IGNORE:-}"

    # Execution settings
    WORKER_COUNT="${WORKER_COUNT:-$(nproc 2>/dev/null || echo 4)}"
    DEBUG="${DEBUG:-false}"

    # Common command-line flags
    CHECK_DEPS_ONLY="${CHECK_DEPS_ONLY:-false}"
    LIST_IMAGES="${LIST_IMAGES:-false}"
    LIST_TESTS="${LIST_TESTS:-false}"
    CREATE_SNAPSHOT="${CREATE_SNAPSHOT:-false}"
    AUTO_YES="${AUTO_YES:-false}"
    FORCE_MATRIX_REBUILD="${FORCE_MATRIX_REBUILD:-false}"
    FORCE_IMAGE_REBUILD="${FORCE_IMAGE_REBUILD:-false}"

    # Export variables that child scripts and global functions need
    export CACHE_DIR
    export TEST_RUN_DIR
    export DEBUG
}
