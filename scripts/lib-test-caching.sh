#!/bin/bash
# Common test matrix caching functions
# Used by both hole-punch and transport test generation

# Compute cache key from impls.yaml + select + ignore + debug
compute_cache_key() {
    local test_select="$1"
    local test_ignore="$2"
    local debug="$3"

    { cat impls.yaml 2>/dev/null; echo "$test_select||$test_ignore||$debug"; } | sha256sum | cut -d' ' -f1
}

# Check if cached test matrix exists and load it
# Returns 0 if cache hit, 1 if cache miss
check_and_load_cache() {
    local cache_key="$1"
    local cache_dir="$2"
    local output_dir="$3"

    local cache_file="$cache_dir/test-matrix/${cache_key}.yaml"

    if [ -f "$cache_file" ]; then
        echo "  ✓ [HIT] Using cached test matrix: ${cache_key:0:8}.yaml"
        cp "$cache_file" "$output_dir/test-matrix.yaml"

        # Show cached test count
        local test_count=$(yq eval '.metadata.totalTests' "$output_dir/test-matrix.yaml")
        echo "  ✓ Loaded $test_count tests from cache"
        return 0
    else
        echo "  → [MISS] Generating new test matrix"
        mkdir -p "$cache_dir/test-matrix"
        return 1
    fi
}

# Save generated test matrix to cache
save_to_cache() {
    local output_dir="$1"
    local cache_key="$2"
    local cache_dir="$3"

    local cache_file="$cache_dir/test-matrix/${cache_key}.yaml"

    cp "$output_dir/test-matrix.yaml" "$cache_file"
    echo "✓ Cached as: ${cache_key:0:8}.yaml"
}
