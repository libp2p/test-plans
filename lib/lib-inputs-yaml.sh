#!/bin/bash
# inputs.yaml generation and loading functions
# Handles capturing and restoring test run configuration

set -euo pipefail

# Generate inputs.yaml file capturing all test run configuration
# Args:
#   $1: output_file - Path to write inputs.yaml
#   $2: test_type - Type of test (transport, perf, hole-punch)
#   $3+: original_args - Original command line arguments
# Usage:
#   generate_inputs_yaml "$TEST_PASS_DIR/inputs.yaml" "transport" "${ORIGINAL_ARGS[@]}"
generate_inputs_yaml() {
    local output_file="$1"
    local test_type="$2"
    shift 2
    local original_args=("$@")

    cat > "$output_file" <<EOF
# Generated inputs.yaml for test run
# This file captures all configuration for reproducibility
# Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)

testType: $test_type

commandLineArgs:
EOF

    # Add command line arguments
    for arg in "${original_args[@]}"; do
        echo "  - \"$arg\"" >> "$output_file"
    done

    cat >> "$output_file" <<EOF

environmentVariables:
  CACHE_DIR: "$CACHE_DIR"
  TEST_RUN_DIR: "$TEST_RUN_DIR"
  SCRIPT_LIB_DIR: "$SCRIPT_LIB_DIR"
  DEBUG: "$DEBUG"
  WORKER_COUNT: "$WORKER_COUNT"
EOF

    # Add test-type-specific environment variables
    case "$test_type" in
        transport)
            cat >> "$output_file" <<EOF
  TEST_SELECT: "$TEST_SELECT"
  TEST_IGNORE: "$TEST_IGNORE"
  FORCE_MATRIX_REBUILD: "$FORCE_MATRIX_REBUILD"
  FORCE_IMAGE_REBUILD: "$FORCE_IMAGE_REBUILD"
EOF
            ;;
        perf)
            cat >> "$output_file" <<EOF
  TEST_SELECT: "$TEST_SELECT"
  TEST_IGNORE: "$TEST_IGNORE"
  BASELINE_SELECT: "${BASELINE_SELECT:-}"
  BASELINE_IGNORE: "${BASELINE_IGNORE:-}"
  ITERATIONS: "${ITERATIONS:-10}"
  UPLOAD_BYTES: "${UPLOAD_BYTES:-}"
  DOWNLOAD_BYTES: "${DOWNLOAD_BYTES:-}"
  DURATION: "${DURATION:-}"
  LATENCY_ITERATIONS: "${LATENCY_ITERATIONS:-}"
  FORCE_MATRIX_REBUILD: "$FORCE_MATRIX_REBUILD"
  FORCE_IMAGE_REBUILD: "$FORCE_IMAGE_REBUILD"
EOF
            ;;
        hole-punch)
            cat >> "$output_file" <<EOF
  TEST_SELECT: "$TEST_SELECT"
  TEST_IGNORE: "$TEST_IGNORE"
  RELAY_SELECT: "${RELAY_SELECT:-}"
  RELAY_IGNORE: "${RELAY_IGNORE:-}"
  ROUTER_SELECT: "${ROUTER_SELECT:-}"
  ROUTER_IGNORE: "${ROUTER_IGNORE:-}"
  FORCE_MATRIX_REBUILD: "$FORCE_MATRIX_REBUILD"
  FORCE_IMAGE_REBUILD: "$FORCE_IMAGE_REBUILD"
EOF
            ;;
    esac

    echo "  ✓ Generated inputs.yaml: $output_file"
}

# Load configuration from inputs.yaml if it exists
# This function should be called at the start of run.sh before argument parsing
# Returns: 0 if loaded, 1 if not found
load_inputs_yaml() {
    local inputs_file="${1:-inputs.yaml}"

    if [ ! -f "$inputs_file" ]; then
        return 1
    fi

    echo "→ Loading configuration from $inputs_file"

    # Load environment variables
    while IFS='=' read -r key value; do
        if [ -n "$key" ] && [ -n "$value" ]; then
            export "$key"="$value"
        fi
    done < <(yq eval '.environmentVariables | to_entries | .[] | .key + "=" + .value' "$inputs_file" 2>/dev/null)

    return 0
}

# Get command-line arguments from inputs.yaml
# Returns command-line args, one per line
# Args:
#   $1: inputs_file - Path to inputs.yaml (default: inputs.yaml)
# Returns:
#   Command-line arguments from inputs.yaml, one per line
# Usage:
#   mapfile -t YAML_ARGS < <(get_yaml_args "inputs.yaml")
get_yaml_args() {
    local inputs_file="${1:-inputs.yaml}"

    if [ ! -f "$inputs_file" ]; then
        return 1
    fi

    # Extract command-line args from inputs.yaml
    yq eval '.commandLineArgs[]' "$inputs_file" 2>/dev/null || true
}

# Modify inputs.yaml for snapshot context
# Updates paths to be relative to snapshot directory
# Args:
#   $1: snapshot_dir - Snapshot directory path
modify_inputs_for_snapshot() {
    local snapshot_dir="$1"
    local inputs_file="$snapshot_dir/inputs.yaml"

    if [ ! -f "$inputs_file" ]; then
        echo "  ✗ Warning: inputs.yaml not found, skipping modification"
        return 1
    fi

    # Override paths for snapshot context
    yq eval -i '.environmentVariables.CACHE_DIR = "./"' "$inputs_file"
    yq eval -i '.environmentVariables.TEST_RUN_DIR = "./re-run"' "$inputs_file"
    yq eval -i '.environmentVariables.SCRIPT_LIB_DIR = "./lib"' "$inputs_file"

    # Add DOCKER_IMAGES variable for snapshot image loading
    yq eval -i '.environmentVariables.DOCKER_IMAGES = "./images"' "$inputs_file"

    # Remove snapshot flag from command line args if present
    yq eval -i 'del(.commandLineArgs[] | select(. == "--snapshot"))' "$inputs_file"

    echo "  ✓ Modified inputs.yaml for snapshot context"
    return 0
}
