#!/bin/bash
# Common test execution utilities
# Used by transport, perf, and hole-punch test runners

# Calculate number of unique Docker images required for a test matrix
# Extracts unique dialer and listener implementations from test matrix
# For perf tests, also includes baselines section
get_required_image_count() {
    local test_matrix_file="$1"
    local include_baselines="${2:-false}"  # For perf tests

    if [ ! -f "${test_matrix_file}" ]; then
        echo "0"
        return 1
    fi

    # Create temp file for unique implementations
    local temp_file=$(mktemp)

    # Extract dialers and listeners from tests section
    yq eval '.tests[].dialer' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true
    yq eval '.tests[].listener' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true

    # For perf tests, also include baselines
    if [ "${include_baselines}" == "true" ]; then
        yq eval '.baselines[].dialer' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true
        yq eval '.baselines[].listener' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true
    fi

    # Count unique implementations
    local unique_count=$(sort -u "${temp_file}" | grep -v '^$' | wc -l)

    rm -f "${temp_file}"
    echo "${unique_count}"
}

# Get list of unique Docker images required (pipe-separated)
# Used for filtering in build-images.sh
get_required_images() {
    local test_matrix_file="$1"
    local include_baselines="${2:-false}"

    if [ ! -f "${test_matrix_file}" ]; then
        echo ""
        return 1
    fi

    # Create temp file
    local temp_file=$(mktemp)

    # Extract dialers and listeners
    yq eval '.tests[].dialer' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true
    yq eval '.tests[].listener' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true

    # Include baselines if requested
    if [ "${include_baselines}" == "true" ]; then
        yq eval '.baselines[].dialer' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true
        yq eval '.baselines[].listener' "${test_matrix_file}" 2>/dev/null >> "${temp_file}" || true
    fi

    # Get unique list as pipe-separated string
    local unique_list=$(sort -u "${temp_file}" | grep -v '^$' | paste -sd'|')

    rm -f "${temp_file}"
    echo "${unique_list}"
}
