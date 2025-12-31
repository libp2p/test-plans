#!/bin/bash
# Common test matrix caching functions
# Used by both hole-punch and transport test generation

# Source formatting library if not already loaded
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$_this_script_dir/lib-output-formatting.sh"
fi

# Compute cache key for the test run from images.yaml + any other parameters
#
# Usage:
# compute_test_run_key "images.yaml"
compute_test_run_key() {
  local images_yaml="$1"
  shift

  # 1. Load contents of $images_yaml file
  local contents=$(<"$images_yaml")

  # 2. Remaining arguments joined with '||'
  local args
  if (( $# == 0 )); then
    args=""
  else
    args=$(printf '%s\n' "$@" | paste -sd '|' -)
  fi
 
  # 3. Calculate the hash of both
  local hash=$(printf '%s' "$contents$args" | sha256sum | cut -d ' ' -f1)

  echo "${hash:0:8}"
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
        print_error "Error: test_name is required" >&2
        return 1
    fi

    # Hash the test name
    local test_hash=$(echo "$test_name" | sha256sum | cut -d' ' -f1)

    # Return first 8 characters
    echo "${test_hash:0:8}"
}

# Check if cached file exists and copy it to the output dir
# Returns 0 if cache hit, 1 if cache miss
check_and_load_cache() {
  local cache_key="$1"
  local cache_dir="$2"
  local output_file="$3"
  local force_rebuild="${4:-false}"  # Optional: force rebuild
  local test_type="${5:-}"  # Optional: test type prefix

  # Use test type prefix if provided
  if [ -n "$test_type" ]; then
    local cache_file="$cache_dir/${test_type}-${cache_key}.yaml"
  else
    local cache_file="$cache_dir/${cache_key}.yaml"
  fi

  # If force rebuild requested, skip cache
  if [ "$force_rebuild" = true ]; then
    print_error "[MISS] Force rebuild requested"
    return 1
  fi

  if [ -f "$cache_file" ]; then
    print_success "[HIT] Using cached file: ${cache_file}"
    cp "$cache_file" "$output_file"
    return 0
  else
    print_error "[MISS] Generating new file"
    return 1
  fi
}

# Save generated test matrix to cache
save_to_cache() {
  local output_file="$1"
  local cache_key="$2"
  local cache_dir="$3"
  local test_type="${4:-}"  # Optional: test type prefix

  # Use test type prefix if provided
  if [ -n "$test_type" ]; then
    local cache_file="$cache_dir/${test_type}-${cache_key}.yaml"
  else
    local cache_file="$cache_dir/${cache_key}.yaml"
  fi

  # Copy the generated test-matrix.yaml file to the cache location
  cp "$output_file" "$cache_file"

  print_success "Cached as: ${cache_file}"
}
