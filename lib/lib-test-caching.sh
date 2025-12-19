#!/bin/bash
# Common test matrix caching functions
# Used by both hole-punch and transport test generation

# Compute cache key from images.yaml + select + ignore + relay/router filters + debug
# Supports both transport (3 params) and hole-punch (7 params) usage
compute_cache_key() {
    local test_select="$1"
    local test_ignore="$2"
    local relay_select="${3:-}"      # Optional for hole-punch
    local relay_ignore="${4:-}"      # Optional for hole-punch
    local router_select="${5:-}"     # Optional for hole-punch
    local router_ignore="${6:-}"     # Optional for hole-punch
    local debug="${7:-false}"        # Defaults to false if not provided

    # Include all parameters in hash (empty values are fine)
    { cat images.yaml 2>/dev/null; echo "$test_select||$test_ignore||$relay_select||$relay_ignore||$router_select||$router_ignore||$debug"; } | sha256sum | cut -d' ' -f1
}

# Check if cached test matrix exists and load it
# Returns 0 if cache hit, 1 if cache miss
check_and_load_cache() {
    local cache_key="$1"
    local cache_dir="$2"
    local output_dir="$3"
    local force_rebuild="${4:-false}"  # Optional: force matrix rebuild
    local test_type="${5:-}"  # Optional: test type prefix

    # Use test type prefix if provided
    # Use first 8 chars of cache_key for filename
    if [ -n "$test_type" ]; then
        local cache_file="$cache_dir/test-run-matrix/${test_type}-${cache_key:0:8}.yaml"
    else
        local cache_file="$cache_dir/test-run-matrix/${cache_key:0:8}.yaml"
    fi

    # If force rebuild requested, skip cache
    if [ "$force_rebuild" = true ]; then
        echo "  → [SKIP] Force matrix rebuild requested"
        mkdir -p "$cache_dir/test-run-matrix"
        return 1
    fi

    if [ -f "$cache_file" ]; then
        echo "  ✓ [HIT] Using cached test matrix: ${cache_key:0:8}.yaml"
        cp "$cache_file" "$output_dir/test-matrix.yaml"

        # Show cached test count
        local test_count=$(yq eval '.metadata.totalTests' "$output_dir/test-matrix.yaml")
        echo "  ✓ Loaded $test_count tests from cache"
        return 0
    else
        echo "  → [MISS] Generating new test matrix"
        mkdir -p "$cache_dir/test-run-matrix"
        return 1
    fi
}

# Save generated test matrix to cache
save_to_cache() {
    local output_dir="$1"
    local cache_key="$2"
    local cache_dir="$3"
    local test_type="${4:-}"  # Optional: test type prefix

    # Use test type prefix if provided
    # Use first 8 chars of cache_key for filename
    if [ -n "$test_type" ]; then
        local cache_file="$cache_dir/test-run-matrix/${test_type}-${cache_key:0:8}.yaml"
    else
        local cache_file="$cache_dir/test-run-matrix/${cache_key:0:8}.yaml"
    fi

    mkdir -p "$cache_dir/test-run-matrix"
    cp "$output_dir/test-matrix.yaml" "$cache_file"
    echo "✓ Cached as: ${test_type:+$test_type-}${cache_key:0:8}.yaml"
}
