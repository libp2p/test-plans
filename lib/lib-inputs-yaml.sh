#!/bin/bash
# inputs.yaml generation and modification functions

# Source formatting library if not already loaded
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$_this_script_dir/lib-output-formatting.sh"
fi

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
# Generated inputs.yaml for a "$test_type" test run
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
  IMAGES_YAML: "$IMAGES_YAML"
  CACHE_DIR: "$CACHE_DIR"
  TEST_RUN_DIR: "$TEST_RUN_DIR"
  SCRIPT_DIR: "$SCRIPT_DIR"
  SCRIPT_LIB_DIR: "$SCRIPT_LIB_DIR"
  DEBUG: "$DEBUG"
  WORKER_COUNT: "$WORKER_COUNT"
  TEST_SELECT: "$TEST_SELECT"
  TEST_IGNORE: "$TEST_IGNORE"
  FORCE_MATRIX_REBUILD: "$FORCE_MATRIX_REBUILD"
  FORCE_IMAGE_REBUILD: "$FORCE_IMAGE_REBUILD"
EOF

    # Add test-type-specific environment variables
    case "$test_type" in
        transport)
            cat >> "$output_file" <<EOF
EOF
            ;;
        perf)
            cat >> "$output_file" <<EOF
  BASELINE_SELECT: "${BASELINE_SELECT:-}"
  BASELINE_IGNORE: "${BASELINE_IGNORE:-}"
  ITERATIONS: "${ITERATIONS:-10}"
  UPLOAD_BYTES: "${UPLOAD_BYTES:-}"
  DOWNLOAD_BYTES: "${DOWNLOAD_BYTES:-}"
  DURATION: "${DURATION:-}"
  LATENCY_ITERATIONS: "${LATENCY_ITERATIONS:-}"
EOF
            ;;
        hole-punch)
            cat >> "$output_file" <<EOF
  RELAY_SELECT: "${RELAY_SELECT:-}"
  RELAY_IGNORE: "${RELAY_IGNORE:-}"
  ROUTER_SELECT: "${ROUTER_SELECT:-}"
  ROUTER_IGNORE: "${ROUTER_IGNORE:-}"
EOF
            ;;
    esac

    print_success "Generated inputs.yaml: $output_file"
}

# Modify inputs.yaml for snapshot context
# Updates paths to be relative to snapshot directory
# Args:
#   $1: snapshot_dir - Snapshot directory path
modify_inputs_for_snapshot() {
    local snapshot_dir="$1"
    local inputs_file="$snapshot_dir/inputs.yaml"
    indent

    if [ ! -f "$inputs_file" ]; then
        print_error "Warning: inputs.yaml not found, skipping modification"
        unindent
        return 1
    fi

    # Override paths for snapshot context
    yq eval -i '.environmentVariables.IMAGES_YAML = "./images.yaml"' "$inputs_file"
    yq eval -i '.environmentVariables.CACHE_DIR = "./"' "$inputs_file"
    yq eval -i '.environmentVariables.TEST_RUN_DIR = "./re-run"' "$inputs_file"
    yq eval -i '.environmentVariables.SCRIPT_DIR = "./lib"' "$inputs_file"
    yq eval -i '.environmentVariables.SCRIPT_LIB_DIR = "./lib"' "$inputs_file"

    # Remove snapshot flag from command line args if present
    yq eval -i 'del(.commandLineArgs[] | select(. == "--snapshot"))' "$inputs_file"

    print_success "Modified inputs.yaml for snapshot context"
    unindent
    return 0
}
