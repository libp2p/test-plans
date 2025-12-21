#!/bin/bash
# Main test runner for libp2p transport interoperability tests

set -euo pipefail

# Capture original arguments for inputs.yaml generation
ORIGINAL_ARGS=("$@")

# Change to script directory
cd "$(dirname "$0")"

# ============================================================================
# INLINE inputs.yaml LOADING (self-contained, no external dependencies)
# Avoids bootstrap problem: can't source lib-inputs-yaml.sh before SCRIPT_LIB_DIR is set correctly
# ============================================================================

load_inputs_yaml_inline() {
    local inputs_file="${1:-inputs.yaml}"
    if [ ! -f "$inputs_file" ]; then
        return 1
    fi
    echo "→ Loading configuration from $inputs_file"
    while IFS='=' read -r key value; do
        if [ -n "$key" ] && [ -n "$value" ]; then
            export "$key"="$value"
        fi
    done < <(yq eval '.environmentVariables | to_entries | .[] | .key + "=" + .value' "$inputs_file" 2>/dev/null)
    return 0
}

get_yaml_args_inline() {
    local inputs_file="${1:-inputs.yaml}"
    if [ ! -f "$inputs_file" ]; then
        return 1
    fi
    yq eval '.commandLineArgs[]' "$inputs_file" 2>/dev/null || true
}

# ============================================================================
# BOOTSTRAP: Load inputs.yaml BEFORE setting SCRIPT_LIB_DIR
# ============================================================================

# Step 2 (from the_plan.md): Process inputs.yaml if it exists
if [ -f "inputs.yaml" ]; then
    load_inputs_yaml_inline "inputs.yaml"
    mapfile -t YAML_ARGS < <(get_yaml_args_inline "inputs.yaml")
else
    YAML_ARGS=()
fi

# Step 3 (from the_plan.md): Append actual command-line args (these override inputs.yaml)
CMD_LINE_ARGS=("${YAML_ARGS[@]}" "$@")

# Step 4 (from the_plan.md): Set positional parameters to merged args
set -- "${CMD_LINE_ARGS[@]}"

# NOW set SCRIPT_LIB_DIR (after inputs.yaml loaded, so it can be overridden)
export SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "$0")/.." && pwd)/lib}"

# Initialize common variables (paths, flags, defaults)
source "$SCRIPT_LIB_DIR/lib-common-init.sh"
init_common_variables

# Source formatting library
source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"

print_banner

# Show help
show_help() {
    cat <<EOF
libp2p Transport Interoperability Test Runner

Usage: $0 [options]

Options:
  --test-select VALUE       Select tests (pipe-separated substrings)
  --test-ignore VALUE       Ignore tests (pipe-separated substrings)
  --workers VALUE           Number of parallel workers (default: $(nproc 2>/dev/null || echo 4))
  --cache-dir VALUE         Cache directory (default: /srv/cache)
  --snapshot                Create test pass snapshot after completion
  --debug                   Enable debug mode (sets DEBUG=true in test containers)
  --force-matrix-rebuild    Force regeneration of test matrix (bypass cache)
  --force-image-rebuild     Force rebuilding of all docker images (bypass cache)
  -y, --yes                 Skip confirmation prompt and run tests immediately
  --check-deps              Only check dependencies and exit
  --list-images             List all image types used by this test suite and exit
  --list-tests              List all selected tests and exit
  --help                    Show this help message

Examples:
  $0 --cache-dir /srv/cache --workers 4
  $0 --test-select "rust-v0.53" --workers 8
  $0 --test-ignore "webrtc"
  $0 --test-select "rust-v0.56" --force-matrix-rebuild
  $0 --list-images
  $0 --list-tests --test-select "~libp2p"
  $0 --snapshot --force-image-rebuild

Dependencies:
  bash 4.0+, docker 20.10+, yq 4.0+, wget, zip, unzip
  Run with --check-deps to verify installation.

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test-select) TEST_SELECT="$2"; shift 2 ;;
        --test-ignore) TEST_IGNORE="$2"; shift 2 ;;
        --workers) WORKER_COUNT="$2"; shift 2 ;;
        --cache-dir) CACHE_DIR="$2"; shift 2 ;;
        --snapshot) CREATE_SNAPSHOT=true; shift ;;
        --debug) DEBUG=true; shift ;;
        --force-matrix-rebuild) FORCE_MATRIX_REBUILD=true; shift ;;
        --force-image-rebuild) FORCE_IMAGE_REBUILD=true; shift ;;
        -y|--yes) AUTO_YES=true; shift ;;
        --check-deps) CHECK_DEPS_ONLY=true; shift ;;
        --list-images) LIST_IMAGES=true; shift ;;
        --list-tests) LIST_TESTS=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        *)
            echo "Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

# Source common libraries (after argument parsing, so --help doesn't need them)
source "$SCRIPT_LIB_DIR/lib-test-filtering.sh"
source "$SCRIPT_LIB_DIR/lib-test-caching.sh"
source "$SCRIPT_LIB_DIR/lib-image-naming.sh"

# List images
if [ "$LIST_IMAGES" = true ]; then
    if [ ! -f "images.yaml" ]; then
        print_error "images.yaml not found"
        exit 1
    fi

    source "$SCRIPT_LIB_DIR/lib-test-aliases.sh"

    print_header "Available Images"

    # Get and print implementations
    all_image_ids=($(get_entity_ids "implementations"))
    print_list "implementations" "${all_image_ids[@]}"

    echo ""
    exit 0
fi

# List tests
if [ "$LIST_TESTS" = true ]; then
    # Create temporary directory for test matrix generation
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    export TEST_PASS_DIR="$TEMP_DIR"
    export TEST_PASS_NAME="temp-list"
    export CACHE_DIR
    export DEBUG
    export TEST_SELECT TEST_IGNORE BASELINE_SELECT BASELINE_IGNORE
    export UPLOAD_BYTES DOWNLOAD_BYTES
    export ITERATIONS DURATION_PER_ITERATION LATENCY_ITERATIONS
    export FORCE_MATRIX_REBUILD

    print_header "Generating test matrix..."

    # Generate test matrix (don't suppress output to show Test Matrix Generation section)
    bash lib/generate-tests.sh || true

    # Check if matrix was created successfully
    if [ ! -f "$TEMP_DIR/test-matrix.yaml" ]; then
        echo "Error: Failed to generate test matrix"
        bash lib/generate-tests.sh 2>&1 | tail -10  # Show error output
        exit 1
    fi

    # Extract and display test counts
    test_count=$(yq eval '.metadata.totalTests' "$TEMP_DIR/test-matrix.yaml")
    ignored_count=$(yq eval '.metadata.ignoredTests' "$TEMP_DIR/test-matrix.yaml")


    echo ""
    print_header "Selected Main Tests ($test_count tests)"
    if [ "$test_count" -gt 0 ]; then
        yq eval '.tests[].name' "$TEMP_DIR/test-matrix.yaml" | while read -r name; do
            echo "  ✓ $name"
        done
    else
        echo "  → No main tests selected"
    fi

    ignored_test_count=$(yq eval '.metadata.ignoredTests' "$TEMP_DIR/test-matrix.yaml" 2>/dev/null || echo 0)
    echo ""
    print_header "Ignored Main Tests ($ignored_test_count tests)"
    if [ "$ignored_test_count" -gt 0 ]; then
        yq eval '.ignoredTests[].name' "$TEMP_DIR/test-matrix.yaml" | while read -r name; do
            echo "  ✗ $name"
        done
    else
        echo "  → No main tests ignored"
    fi

    echo ""
    echo "  → Total selected: $test_count tests"
    echo "  → Total ignored: $ignored_test_count tests"
    echo ""
    exit 0
fi

# Check dependencies
if [ "$CHECK_DEPS_ONLY" = true ]; then
    bash "$SCRIPT_LIB_DIR/check-dependencies.sh"
    exit $?
fi

# Export variables for child scripts
export DEBUG
export CACHE_DIR

print_header "Transport Interoperability Test Suite"

# Source test key generation functions
source "$SCRIPT_LIB_DIR/lib-test-keys.sh"

# Generate test run key and test pass name
TEST_TYPE="transport"
TEST_RUN_KEY=$(compute_test_run_key "images.yaml" "$TEST_SELECT||$TEST_IGNORE||$DEBUG")
TEST_PASS_NAME="${TEST_TYPE}-${TEST_RUN_KEY}-$(date +%H%M%S-%d-%m-%Y)"
export TEST_PASS_DIR="$TEST_RUN_DIR/$TEST_PASS_NAME"
mkdir -p "$TEST_PASS_DIR"/{logs,results,docker-compose}
export TEST_RUN_KEY

# Generate inputs.yaml for reproducibility
source "$SCRIPT_LIB_DIR/lib-inputs-yaml.sh"
generate_inputs_yaml "$TEST_PASS_DIR/inputs.yaml" "$TEST_TYPE" "${ORIGINAL_ARGS[@]}"

export TEST_PASS_DIR
export TEST_PASS_NAME

echo ""
print_header "libp2p Transport Test Suite"

echo "→ Test Pass: $TEST_PASS_NAME"
echo "→ Cache Dir: $CACHE_DIR"
echo "→ Test Pass Dir: $TEST_PASS_DIR"
echo "→ Workers: $WORKER_COUNT"
[ -n "$TEST_SELECT" ] && echo "→ Test Select: $TEST_SELECT"
[ -n "$TEST_IGNORE" ] && echo "→ Test Ignore: $TEST_IGNORE"
echo "→ Create Snapshot: $CREATE_SNAPSHOT"
echo "→ Debug: $DEBUG"
echo "→ Force Matrix Rebuild: $FORCE_MATRIX_REBUILD"
echo "→ Force Image Rebuild: $FORCE_IMAGE_REBUILD"
echo ""

# Check dependencies for normal execution
print_header "Checking dependencies..."
bash "$SCRIPT_LIB_DIR/check-dependencies.sh" docker yq || {
  echo ""
  echo "  ✗ Error: Missing required dependencies."
  echo "  → Run '$0 --check-deps' to see details."
  exit 1
}

# Start timing (moved before server setup)
TEST_START_TIME=$(date +%s)

export TEST_PASS_NAME
echo ""

# Read and export the docker compose command detected by check-dependencies.sh
if [ -f /tmp/docker-compose-cmd.txt ]; then
    export DOCKER_COMPOSE_CMD=$(cat /tmp/docker-compose-cmd.txt)
    echo "→ Using: $DOCKER_COMPOSE_CMD"
else
    echo "✗ Error: Could not determine docker compose command"
    exit 1
fi

# 2. Generate test matrix FIRST (before building images)
echo ""
print_header "Generating test matrix"

# Export variables for generate-tests.sh
export TEST_PASS_DIR
export CACHE_DIR
export DEBUG
export TEST_SELECT
export TEST_IGNORE
export FORCE_MATRIX_REBUILD

echo "→ bash lib/generate-tests.sh"
bash lib/generate-tests.sh

# 3. Display test selection and get confirmation
echo ""
print_header "Test selection..."
echo "→ Selected tests:"

# Read test matrix
test_count=$(yq eval '.metadata.totalTests' "$TEST_PASS_DIR/test-matrix.yaml")
ignored_count=$(yq eval '.metadata.ignoredTests' "$TEST_PASS_DIR/test-matrix.yaml")

# Display active tests (extract all names in one yq call)
if [ "$test_count" -gt 0 ]; then
    yq eval '.tests[].name' "$TEST_PASS_DIR/test-matrix.yaml" | while read -r test_name; do
        echo "  ✓ $test_name"
    done
fi

# Display ignored tests (extract all names in one yq call)
if [ "$ignored_count" -gt 0 ]; then
    echo ""
    echo "→ Ignored tests:"
    yq eval '.ignoredTests[].name' "$TEST_PASS_DIR/test-matrix.yaml" | while read -r test_name; do
        echo "  ✗ $test_name [ignored]"
    done
fi

echo ""
echo "→ Total: $test_count tests to execute, $ignored_count ignored"

# Source common test execution utilities
source "$SCRIPT_LIB_DIR/lib-test-execution.sh"

# Calculate required Docker images
image_count=$(get_required_image_count "$TEST_PASS_DIR/test-matrix.yaml" "false")
echo "→ Required Docker images: $image_count"

# Prompt user for confirmation (unless -y flag was set)
if [ "$AUTO_YES" = false ]; then
    echo ""
    read -p "Build $image_count Docker images and execute $test_count tests? (Y/n): " response
    response=${response:-Y}  # Default to Y if user just presses enter

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Test execution cancelled."
        exit 0
    fi
fi

# 4. Extract unique implementations from test matrix and build only those
echo ""
print_header "Building Docker images..."

# Check if test matrix has any tests
if [ "$test_count" -eq 0 ]; then
    echo "→ No tests in matrix, skipping image builds"
else
    # Get unique implementations from test matrix (dialer + listener)
    REQUIRED_IMAGES=$(mktemp)
    yq eval '.tests[].dialer' "$TEST_PASS_DIR/test-matrix.yaml" | sort -u > "$REQUIRED_IMAGES"
    yq eval '.tests[].listener' "$TEST_PASS_DIR/test-matrix.yaml" | sort -u >> "$REQUIRED_IMAGES"
    sort -u "$REQUIRED_IMAGES" -o "$REQUIRED_IMAGES"

    # Also add base images for any browser-type implementations
    REQUIRED_IMPLS_WITH_DEPS=$(mktemp)
    cp "$REQUIRED_IMAGES" "$REQUIRED_IMPLS_WITH_DEPS"

    while IFS= read -r image_id; do
        # Check if this is a browser-type implementation
        source_type=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .source.type" images.yaml)
        if [ "$source_type" = "browser" ]; then
            # Add its base image as a dependency
            base_image=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .source.baseImage" images.yaml)
            echo "$base_image" >> "$REQUIRED_IMPLS_WITH_DEPS"
        fi
    done < "$REQUIRED_IMAGES"

    # Sort and deduplicate
    sort -u "$REQUIRED_IMPLS_WITH_DEPS" -o "$REQUIRED_IMPLS_WITH_DEPS"

    IMAGE_COUNT=$(wc -l < "$REQUIRED_IMPLS_WITH_DEPS")
    echo "→ Building $IMAGE_COUNT required implementations (including base images)"
    echo ""

    # Build each required implementation using pipe-separated list
    IMAGE_FILTER=$(cat "$REQUIRED_IMPLS_WITH_DEPS" | paste -sd'|' -)
    echo "→ bash lib/build-images.sh \"$IMAGE_FILTER\" \"$FORCE_IMAGE_REBUILD\""
    bash lib/build-images.sh "$IMAGE_FILTER" "$FORCE_IMAGE_REBUILD"

    rm -f "$REQUIRED_IMAGES" "$REQUIRED_IMPLS_WITH_DEPS"
fi

# Start global services
echo ""
bash lib/start-global-services.sh || {
    print_error "Starting global services failed"
}


# 4. Run tests in parallel
echo ""
print_header "Running tests... ($WORKER_COUNT workers)"

# Read test matrix and export test_count for use in subshells
test_count=$(yq eval '.metadata.totalTests' "$TEST_PASS_DIR/test-matrix.yaml")
export test_count

# Note: Individual results will be saved to results/ directory

# Run tests with parallel workers
run_test() {
    local index=$1
    local name=$(yq eval ".tests[$index].name" "$TEST_PASS_DIR/test-matrix.yaml")
    local dialer=$(yq eval ".tests[$index].dialer" "$TEST_PASS_DIR/test-matrix.yaml")
    local listener=$(yq eval ".tests[$index].listener" "$TEST_PASS_DIR/test-matrix.yaml")
    local transport=$(yq eval ".tests[$index].transport" "$TEST_PASS_DIR/test-matrix.yaml")
    local secure=$(yq eval ".tests[$index].secureChannel" "$TEST_PASS_DIR/test-matrix.yaml")
    local muxer=$(yq eval ".tests[$index].muxer" "$TEST_PASS_DIR/test-matrix.yaml")

    echo "[$((index + 1))/$test_count] $name"

    start=$(date +%s)
    if bash lib/run-single-test.sh "$name" "$dialer" "$listener" "$transport" "$secure" "$muxer"; then
        status="pass"
        exit_code=0
    else
        status="fail"
        exit_code=1
    fi
    end=$(date +%s)
    duration=$((end - start))

    # Extract metrics from log file if test passed
    handshake_ms=""
    ping_ms=""
    if [ "$status" = "pass" ]; then
        test_slug=$(echo "$name" | sed 's/[^a-zA-Z0-9-]/_/g')
        log_file="$TEST_PASS_DIR/logs/${test_slug}.log"
        if [ -f "$log_file" ]; then
            # Extract JSON metrics from log
            metrics=$(grep -o '{"handshakePlusOneRTTMillis":[0-9.]*,"pingRTTMilllis":[0-9.]*}' "$log_file" 2>/dev/null | tail -1)
            if [ -n "$metrics" ]; then
                handshake_ms=$(echo "$metrics" | grep -o '"handshakePlusOneRTTMillis":[0-9.]*' | cut -d: -f2)
                ping_ms=$(echo "$metrics" | grep -o '"pingRTTMilllis":[0-9.]*' | cut -d: -f2)
            fi
        fi
    fi

    # Compute test key for this individual test
    source "$SCRIPT_LIB_DIR/lib-test-keys.sh"
    TEST_KEY=$(compute_test_key "$name")

    # Save individual test result
    cat > "$TEST_PASS_DIR/results/${TEST_KEY}.yaml" <<EOF
name: $name
status: $status
exitCode: $exit_code
duration: ${duration}s
dialer: $dialer
listener: $listener
transport: $transport
secureChannel: $secure
muxer: $muxer
EOF

    # Add metrics if available
    if [ -n "$handshake_ms" ]; then
        echo "handshakePlusOneRTTMs: $handshake_ms" >> "$TEST_PASS_DIR/results/${TEST_KEY}.yaml"
    fi
    if [ -n "$ping_ms" ]; then
        echo "pingRTTMs: $ping_ms" >> "$TEST_PASS_DIR/results/${TEST_KEY}.yaml"
    fi

    return $exit_code
}

export -f run_test

# Run tests in parallel using xargs
# Note: Some tests may fail, but we want to continue to collect results
# So we use || true to ensure xargs exit code doesn't stop the script
seq 0 $((test_count - 1)) | xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}' || true


# Stop global services
echo ""
bash lib/stop-global-services.sh || {
    echo ""
    print_error "Stopping global services failed"
}

# 5. Collect results
echo ""
print_header "Collecting results..."


END_TIME=$(date +%s)
DURATION=$((END_TIME - TEST_START_TIME))


# Count pass/fail from individual result files
PASSED=$(grep -h "^status: pass" "$TEST_PASS_DIR"/results/*.yaml 2>/dev/null | wc -l)
FAILED=$(grep -h "^status: fail" "$TEST_PASS_DIR"/results/*.yaml 2>/dev/null | wc -l)

# Handle empty results
PASSED=${PASSED:-0}
FAILED=${FAILED:-0}


# Generate final results.yaml
cat > "$TEST_PASS_DIR/results.yaml" <<EOF
metadata:
  testPass: $TEST_PASS_NAME
  startedAt: $(date -d @$TEST_START_TIME -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -r $TEST_START_TIME -u +%Y-%m-%dT%H:%M:%SZ)
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration: ${DURATION}s
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: $WORKER_COUNT

summary:
  total: $test_count
  passed: $PASSED
  failed: $FAILED

tests:
EOF

# Aggregate individual result files into results.yaml
for result_file in "$TEST_PASS_DIR"/results/*.yaml; do
    if [ -f "$result_file" ]; then
        # Read first line and add as array item
        echo "  - name: $(yq eval '.name' "$result_file")" >> "$TEST_PASS_DIR/results.yaml"
        # Add remaining fields with proper indentation
        yq eval 'del(.name) | to_entries | .[] | "    " + .key + ": " + (.value | @json)' "$result_file" | sed 's/"//g' >> "$TEST_PASS_DIR/results.yaml"
    fi
done

# NOW collect failed test names (after aggregation is complete)
FAILED_TESTS=()
if [ "$FAILED" -gt 0 ]; then
    readarray -t FAILED_TESTS < <(yq eval '.tests[] | select(.status == "fail") | .name' "$TEST_PASS_DIR/results.yaml" 2>/dev/null || true)
fi

echo "→ Results:"
echo "  → Total: $test_count"
echo "  ✓ Passed: $PASSED"
echo "  ✗ Failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then
    for test_name in "${FAILED_TESTS[@]}"; do
        echo "    - $test_name"
    done
fi
echo ""

# Display execution time
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))
printf "→ Total time: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS

# 6. Generate dashboard
echo ""
print_header "Generating results dashboard..."
bash lib/generate-dashboard.sh || {
    echo "  ✗ Dashboard generation failed"
}

echo ""
if [ "$FAILED" -eq 0 ]; then
    print_success "All tests passed!"
    EXIT_FINAL=0
else
    print_error "$FAILED test(s) failed"
    EXIT_FINAL=1
fi

# 7. Create snapshot (if requested)
if [ "$CREATE_SNAPSHOT" = true ]; then
    echo ""
    print_header "Creating test pass snapshot..."
    bash lib/create-snapshot.sh || {
        echo "  ✗ Snapshot creation failed"
    }
fi

exit $EXIT_FINAL
