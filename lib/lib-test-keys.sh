#!/bin/bash
# Test key generation functions
# Provides functions for computing unique identifiers for test runs and individual tests

set -euo pipefail

# Compute test run key (8-char hex) from inputs and images configuration
# This creates a unique identifier for each test run configuration
#
# Args:
#   $1: images_file - Path to images.yaml (default: images.yaml)
#   $2: Additional parameters to include in hash (optional)
# Returns:
#   8-character hexadecimal string
# Usage:
#   TEST_RUN_KEY=$(compute_test_run_key "images.yaml" "$TEST_SELECT||$TEST_IGNORE||$DEBUG")
compute_test_run_key() {
    local images_file="${1:-images.yaml}"
    local extra_params="${2:-}"

    # Check if images.yaml exists
    if [ ! -f "$images_file" ]; then
        echo "Error: $images_file not found" >&2
        return 1
    fi

    # Hash the images.yaml file
    local images_hash=$(sha256sum "$images_file" | cut -d' ' -f1)

    # If extra parameters provided, include them in the hash
    if [ -n "$extra_params" ]; then
        local combined_hash=$(echo "${images_hash}||${extra_params}" | sha256sum | cut -d' ' -f1)
    else
        local combined_hash="$images_hash"
    fi

    # Return first 8 characters
    echo "${combined_hash:0:8}"
}

# Compute test key (8-char hex) from test name
# This creates a unique identifier for each individual test
#
# Args:
#   $1: test_name - Full name of the test
# Returns:
#   8-character hexadecimal string
# Usage:
#   TEST_KEY=$(compute_test_key "$test_name")
compute_test_key() {
    local test_name="$1"

    if [ -z "$test_name" ]; then
        echo "Error: test_name is required" >&2
        return 1
    fi

    # Hash the test name
    local test_hash=$(echo "$test_name" | sha256sum | cut -d' ' -f1)

    # Return first 8 characters
    echo "${test_hash:0:8}"
}

# Compute cache key for test matrix (for backwards compatibility)
# This maintains compatibility with existing caching system
#
# Args:
#   $1: test_type - Type of test (transport, perf, hole-punch)
#   $2: test_run_key - 8-char test run key
# Returns:
#   Cache key string
# Usage:
#   CACHE_KEY=$(compute_test_matrix_cache_key "$TEST_TYPE" "$TEST_RUN_KEY")
compute_test_matrix_cache_key() {
    local test_type="$1"
    local test_run_key="$2"

    echo "${test_type}-${test_run_key}"
}
