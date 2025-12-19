#!/bin/bash
# Main test runner for libp2p performance benchmarks
# Similar structure to transport/run_tests.sh and hole-punch/run_tests.sh

set -euo pipefail

# Capture original arguments for inputs.yaml generation
ORIGINAL_ARGS=("$@")

# Default parameters
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_RUN_DIR="${TEST_RUN_DIR:-$CACHE_DIR/test-run}"
TEST_SELECT="${TEST_SELECT:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
BASELINE_SELECT="${BASELINE_SELECT:-}"
BASELINE_IGNORE="${BASELINE_IGNORE:-}"
UPLOAD_BYTES=1073741824     # 1GB default
DOWNLOAD_BYTES=1073741824   # 1GB default
ITERATIONS=10
DURATION_PER_ITERATION=20   # seconds per iteration for throughput tests
LATENCY_ITERATIONS=100      # iterations for latency test
SNAPSHOT=false
FORCE_MATRIX_REBUILD=false
FORCE_IMAGE_REBUILD=false
DEBUG=false
AUTO_APPROVE=false
CHECK_DEPS_ONLY=false
LIST_IMAGES=false
LIST_TESTS=false

# Change to script directory
cd "$(dirname "$0")"

# Set global library directory
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "$0")/.." && pwd)/lib}"

# Source formatting library
source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"

print_banner

# Show help
show_help() {
    cat <<EOF
libp2p Performance Test Runner

Usage: $0 [options]

Options:
  --test-select VALUE           Select implementations to test (pipe-separated)
  --test-ignore VALUE           Ignore implementations (pipe-separated)
  --baseline-select VALUE       Select baseline tests (pipe-separated)
  --baseline-ignore VALUE       Ignore baseline tests (pipe-separated)
  --upload-bytes VALUE          Bytes to upload per test (default: 1GB)
  --download-bytes VALUE        Bytes to download per test (default: 1GB)
  --iterations VALUE            Number of iterations per test (default: 10)
  --duration VALUE              Duration per iteration for throughput (default: 20s)
  --latency-iterations VALUE    Iterations for latency test (default: 100)
  --cache-dir VALUE             Cache directory (default: /srv/cache)
  --snapshot                    Create test pass snapshot after completion
  --force-matrix-rebuild        Force test matrix regeneration (bypass cache)
  --force-image-rebuild         Force Docker image rebuilds (bypass cache)
  --debug                       Enable debug mode
  -y, --yes                     Skip confirmation prompts
  --check-deps                  Only check dependencies and exit
  --list-images                 List all image types used by this test suite and exit
  --list-tests                  List all selected tests and exit
  --help, -h                    Show this help message

Examples:
  $0 --cache-dir /srv/cache --workers 4
  $0 --test-select "go-v0.45" --iterations 3
  $0 --test-select "~libp2p" --snapshot
  $0 --test-ignore "js-v3.x"
  $0 --upload-bytes 5368709120 --download-bytes 5368709120
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
        --baseline-select) BASELINE_SELECT="$2"; shift 2 ;;
        --baseline-ignore) BASELINE_IGNORE="$2"; shift 2 ;;
        --upload-bytes) UPLOAD_BYTES="$2"; shift 2 ;;
        --download-bytes) DOWNLOAD_BYTES="$2"; shift 2 ;;
        --iterations) ITERATIONS="$2"; shift 2 ;;
        --duration) DURATION_PER_ITERATION="$2"; shift 2 ;;
        --latency-iterations) LATENCY_ITERATIONS="$2"; shift 2 ;;
        --cache-dir) CACHE_DIR="$2"; shift 2 ;;
        --snapshot) SNAPSHOT=true; shift ;;
        --force-matrix-rebuild) FORCE_MATRIX_REBUILD=true; shift ;;
        --force-image-rebuild) FORCE_IMAGE_REBUILD=true; shift ;;
        --debug) DEBUG=true; shift ;;
        -y|--yes) AUTO_APPROVE=true; shift ;;
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
source "lib/lib-perf.sh"

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

    # Get and print baselines
    all_baseline_ids=($(get_entity_ids "baselines"))
    print_list "baselines" "${all_baseline_ids[@]}"

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

    # Extract and display test counts (selected and ignored)
    baseline_count=$(yq eval '.metadata.totalBaselines' "$TEMP_DIR/test-matrix.yaml")
    ignored_baseline_count=$(yq eval '.metadata.ignoredBaselines' "$TEMP_DIR/test-matrix.yaml")
    test_count=$(yq eval '.metadata.totalTests' "$TEMP_DIR/test-matrix.yaml")
    ignored_test_count=$(yq eval '.metadata.ignoredTests' "$TEMP_DIR/test-matrix.yaml")

    echo ""
    print_header "Selected Baseline Tests ($baseline_count tests)"
    if [ "$baseline_count" -gt 0 ]; then
        yq eval '.baselines[].name' "$TEMP_DIR/test-matrix.yaml" | while read -r name; do
            echo "  ✓ $name"
        done
    else
        echo "  → No baseline tests selected"
    fi

    echo ""
    print_header "Ignored Baseline Tests ($ignored_baseline_count tests)"
    if [ "$ignored_baseline_count" -gt 0 ]; then
        yq eval '.ignoredBaselines[].name' "$TEMP_DIR/test-matrix.yaml" | while read -r name; do
            echo "  ✗ $name"
        done
    else
        echo "  → No baseline tests ignored"
    fi

    echo ""
    print_header "Selected Main Tests ($test_count tests)"
    if [ "$test_count" -gt 0 ]; then
        yq eval '.tests[].name' "$TEMP_DIR/test-matrix.yaml" | while read -r name; do
            echo "  ✓ $name"
        done
    else
        echo "  → No main tests selected"
    fi

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
    echo "  → Total selected: $baseline_count baseline + $test_count main = $((baseline_count + test_count)) tests"
    echo "  → Total ignored: $ignored_baseline_count baseline + $ignored_test_count main = $((ignored_baseline_count + ignored_test_count)) tests"
    echo ""
    exit 0
fi

# Check dependencies
if [ "$CHECK_DEPS_ONLY" = true ]; then
    bash "$SCRIPT_LIB_DIR/check-dependencies.sh" docker yq
    exit $?
fi

# Export variables for child scripts
export DEBUG
export CACHE_DIR

# Source test key generation functions
source "$SCRIPT_LIB_DIR/lib-test-keys.sh"

# Generate test run key and test pass name
TEST_TYPE="perf"
TEST_RUN_KEY=$(compute_test_run_key "images.yaml" "$TEST_SELECT||$TEST_IGNORE||$BASELINE_SELECT||$BASELINE_IGNORE||$DEBUG||$ITERATIONS")
TEST_PASS_NAME="${TEST_TYPE}-${TEST_RUN_KEY}-$(date +%H%M%S-%d-%m-%Y)"
TEST_PASS_DIR="$TEST_RUN_DIR/$TEST_PASS_NAME"
mkdir -p "$TEST_PASS_DIR"/{logs,results,baseline}
export TEST_RUN_KEY

# Generate inputs.yaml for reproducibility
source "$SCRIPT_LIB_DIR/lib-inputs-yaml.sh"
generate_inputs_yaml "$TEST_PASS_DIR/inputs.yaml" "$TEST_TYPE" "${ORIGINAL_ARGS[@]}"

export TEST_PASS_DIR
export TEST_PASS_NAME

echo ""
print_header "libp2p Performance Test Suite"

echo "  → Test Pass: $TEST_PASS_NAME"
echo "  → Cache Dir: $CACHE_DIR"
echo "  → Test Pass Dir: $TEST_PASS_DIR"
[ -n "$TEST_SELECT" ] && echo "  → Test Select: $TEST_SELECT"
[ -n "$TEST_IGNORE" ] && echo "  → Test Ignore: $TEST_IGNORE"
echo "  → Upload Bytes: $(numfmt --to=iec --suffix=B $UPLOAD_BYTES 2>/dev/null || echo "${UPLOAD_BYTES} bytes")"
echo "  → Download Bytes: $(numfmt --to=iec --suffix=B $DOWNLOAD_BYTES 2>/dev/null || echo "${DOWNLOAD_BYTES} bytes")"
echo "  → Iterations: $ITERATIONS"
echo "  → Duration per Iteration: ${DURATION_PER_ITERATION}s"
echo "  → Latency Iterations: $LATENCY_ITERATIONS"
echo "  → Create Snapshot: $SNAPSHOT"
echo "  → Debug: $DEBUG"
echo "  → Force Matrix Rebuild: $FORCE_MATRIX_REBUILD"
echo "  → Force Image Rebuild: $FORCE_IMAGE_REBUILD"
echo ""

# Check dependencies for normal execution
echo "╲ Checking dependencies..."
bash "$SCRIPT_LIB_DIR/check-dependencies.sh docker yq || {
  echo ""
  echo "Error: Missing required dependencies."
  echo "Run '$0 --check-deps' to see details."
  exit 1
}

# Read and export the docker compose command detected by check-dependencies.sh
if [ -f /tmp/docker-compose-cmd.txt ]; then
    export DOCKER_COMPOSE_CMD=$(cat /tmp/docker-compose-cmd.txt)
    echo "  → Using: $DOCKER_COMPOSE_CMD"
else
    echo "✗ Error: Could not determine docker compose command"
    exit 1
fi
echo ""

# Start timing (moved before server setup)
TEST_START_TIME=$(date +%s)

# Setup remote servers (if any)
echo "╲ Server Setup"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

if [ -f lib/setup-remote-server.sh ]; then
  bash lib/setup-remote-server.sh || {
    log_error "Remote server setup failed"
    exit 1
  }
else
  log_info "No remote server setup script found"
  log_info "Proceeding with local-only testing"
fi

# Generate test matrix
echo ""
echo "╲ Generating test matrix..."

export TEST_SELECT TEST_IGNORE BASELINE_SELECT BASELINE_IGNORE
export UPLOAD_BYTES DOWNLOAD_BYTES
export ITERATIONS DURATION_PER_ITERATION LATENCY_ITERATIONS FORCE_MATRIX_REBUILD

# Show command with filter values (matching transport format)
echo "→ bash lib/generate-tests.sh \"$TEST_SELECT\" \"$TEST_IGNORE\" \"$BASELINE_SELECT\" \"$BASELINE_IGNORE\""

bash lib/generate-tests.sh || {
  echo "✗ Test matrix generation failed"
  exit 1
}

# Display test selection and get confirmation
echo ""
echo "╲ Test selection..."

# Read baseline and main test counts
baseline_count=$(yq eval '.baselines | length' "$TEST_PASS_DIR/test-matrix.yaml" 2>/dev/null || echo "0")
test_count=$(yq eval '.tests | length' "$TEST_PASS_DIR/test-matrix.yaml" 2>/dev/null || echo "0")

# Display baseline tests
if [ "$baseline_count" -gt 0 ]; then
    echo "  → Selected baseline tests:"
    yq eval '.baselines[].name' "$TEST_PASS_DIR/test-matrix.yaml" | while read -r test_name; do
        echo "  ✓ $test_name"
    done
    echo ""
fi

# Display main tests
if [ "$test_count" -gt 0 ]; then
    echo "  → Selected main tests:"
    yq eval '.tests[].name' "$TEST_PASS_DIR/test-matrix.yaml" | while read -r test_name; do
        echo "  ✓ $test_name"
    done
else
    echo "  → No main tests selected"
fi

echo ""
echo "  → Total: $baseline_count baseline tests, $test_count main tests to execute"

# Source common test execution utilities
source "$SCRIPT_LIB_DIR/lib-test-execution.sh"

# Calculate required Docker images
image_count=$(get_required_image_count "$TEST_PASS_DIR/test-matrix.yaml" "true")
print_message "Required Docker images: $image_count"

# Prompt for confirmation unless auto-approved
if [ "$AUTO_APPROVE" != true ]; then
  total_tests=$((baseline_count + test_count))
  read -p "Build $image_count Docker images and execute $total_tests tests ($baseline_count baseline + $test_count main)? (Y/n): " response
  response=${response:-Y}

  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Test execution cancelled."
    exit 0
  fi
fi

# Build Docker images
echo ""
echo "╲ Building Docker images..."

# Get unique implementations from both baselines and main tests
REQUIRED_IMAGES=$(mktemp)
yq eval '.baselines[].dialer' "$TEST_PASS_DIR/test-matrix.yaml" 2>/dev/null | sort -u > "$REQUIRED_IMAGES" || true
yq eval '.baselines[].listener' "$TEST_PASS_DIR/test-matrix.yaml" 2>/dev/null | sort -u >> "$REQUIRED_IMAGES" || true
yq eval '.tests[].dialer' "$TEST_PASS_DIR/test-matrix.yaml" 2>/dev/null | sort -u >> "$REQUIRED_IMAGES" || true
yq eval '.tests[].listener' "$TEST_PASS_DIR/test-matrix.yaml" 2>/dev/null | sort -u >> "$REQUIRED_IMAGES" || true
sort -u "$REQUIRED_IMAGES" -o "$REQUIRED_IMAGES"

IMAGE_COUNT=$(wc -l < "$REQUIRED_IMAGES")
echo "  → Building $IMAGE_COUNT required implementations"
echo ""

# Build each required implementation using pipe-separated list
IMAGE_FILTER=$(cat "$REQUIRED_IMAGES" | paste -sd'|' -)
echo "  → bash lib/build-images.sh \"$IMAGE_FILTER\" \"$FORCE_IMAGE_REBUILD\""
bash lib/build-images.sh "$IMAGE_FILTER" "$FORCE_IMAGE_REBUILD" || {
  echo "✗ Image build failed"
  exit 1
}

rm -f "$REQUIRED_IMAGES"

# Run baseline tests FIRST (before main tests)
if [ "$baseline_count" -gt 0 ]; then
    bash lib/run-baseline.sh || {
      log_info "Baseline tests failed or skipped (not critical)"
    }
fi

# Run main performance tests
echo ""
echo "╲ Running tests... (1 worker)"

for ((i=0; i<test_count; i++)); do
  # Get test name from matrix
  test_name=$(yq eval ".tests[$i].name" "$TEST_PASS_DIR/test-matrix.yaml")

  # Show test progress (matching transport format)
  echo "[$((i + 1))/$test_count] $test_name"

  # Run test, suppress terminal output (still writes to log file)
  bash lib/run-single-test.sh "$i" >/dev/null 2>&1 || {
    log_error "Test $i failed"
    # Continue with other tests
  }
done

# Collect results
echo ""
echo "╲ Collecting results..."

TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

# Count pass/fail from baseline results
BASELINE_PASSED=0
BASELINE_FAILED=0
if [ -f "$TEST_PASS_DIR/baseline-results.yaml.tmp" ]; then
    BASELINE_PASSED=$(grep -c "status: pass" "$TEST_PASS_DIR/baseline-results.yaml.tmp" || true)
    BASELINE_FAILED=$(grep -c "status: fail" "$TEST_PASS_DIR/baseline-results.yaml.tmp" || true)
    BASELINE_PASSED=${BASELINE_PASSED:-0}
    BASELINE_FAILED=${BASELINE_FAILED:-0}
fi

# Count pass/fail from main test results
PASSED=0
FAILED=0
if [ -f "$TEST_PASS_DIR/results.yaml.tmp" ]; then
    PASSED=$(grep -c "status: pass" "$TEST_PASS_DIR/results.yaml.tmp" || true)
    FAILED=$(grep -c "status: fail" "$TEST_PASS_DIR/results.yaml.tmp" || true)
    PASSED=${PASSED:-0}
    FAILED=${FAILED:-0}
fi

# Total counts
TOTAL_PASSED=$((BASELINE_PASSED + PASSED))
TOTAL_FAILED=$((BASELINE_FAILED + FAILED))
TOTAL_TESTS=$((baseline_count + test_count))

# Generate final results.yaml
cat > "$TEST_PASS_DIR/results.yaml" <<EOF
metadata:
  testPass: $TEST_PASS_NAME
  startedAt: $(date -d @$TEST_START_TIME -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -r $TEST_START_TIME -u +%Y-%m-%dT%H:%M:%SZ)
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration: ${TEST_DURATION}s
  platform: $(uname -m)
  os: $(uname -s)

summary:
  totalBaselines: $baseline_count
  baselinesPassed: $BASELINE_PASSED
  baselinesFailed: $BASELINE_FAILED
  totalTests: $test_count
  testsPassed: $PASSED
  testsFailed: $FAILED
  totalAll: $TOTAL_TESTS
  passedAll: $TOTAL_PASSED
  failedAll: $TOTAL_FAILED

baselineResults:
EOF

# Append baseline results if they exist
if [ -f "$TEST_PASS_DIR/baseline-results.yaml.tmp" ]; then
    cat "$TEST_PASS_DIR/baseline-results.yaml.tmp" >> "$TEST_PASS_DIR/results.yaml"
    rm "$TEST_PASS_DIR/baseline-results.yaml.tmp"
fi

cat >> "$TEST_PASS_DIR/results.yaml" <<EOF

testResults:
EOF

# Append main test results if they exist
if [ -f "$TEST_PASS_DIR/results.yaml.tmp" ]; then
    cat "$TEST_PASS_DIR/results.yaml.tmp" >> "$TEST_PASS_DIR/results.yaml"
    rm "$TEST_PASS_DIR/results.yaml.tmp"
fi

echo "  → Results:"
echo "    → Total: $TOTAL_TESTS ($baseline_count baseline + $test_count main)"
echo "    ✓ Passed: $TOTAL_PASSED"
echo "    ✗ Failed: $TOTAL_FAILED"

# List failed tests if any
if [ "$TOTAL_FAILED" -gt 0 ]; then
    readarray -t FAILED_TESTS < <(yq eval '.baselineResults[]?, .testResults[]? | select(.status == "fail") | .name' "$TEST_PASS_DIR/results.yaml" 2>/dev/null || true)
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        for test_name in "${FAILED_TESTS[@]}"; do
            echo "    - $test_name"
        done
    fi
fi
echo ""

# Display execution time
HOURS=$((TEST_DURATION / 3600))
MINUTES=$(((TEST_DURATION % 3600) / 60))
SECONDS=$((TEST_DURATION % 60))
printf "  → Total time: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS

# Generate results dashboard
echo ""
echo "╲ Generating results dashboard..."
echo "  → bash lib/generate-dashboard.sh"

bash lib/generate-dashboard.sh || {
  log_error "Dashboard generation failed"
}

# Generate box plots (optional - requires gnuplot)
echo ""
echo "╲ Generating box plots..."

# Check if gnuplot is available
if command -v gnuplot &> /dev/null; then
    echo "  → bash lib/generate-boxplot.sh"
    bash lib/generate-boxplot.sh "$TEST_PASS_DIR/results.yaml" "$TEST_PASS_DIR" || {
        echo "  ✗ Box plot generation failed"
    }
else
    echo "  ✗ gnuplot not found - skipping box plot generation"
    echo "  Install: apt-get install gnuplot"
fi

# Final status message
echo ""
if [ "$TOTAL_FAILED" -eq 0 ]; then
    echo "╲ ✓ All tests passed!"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    EXIT_FINAL=0
else
    echo "╲ ✗ $TOTAL_FAILED test(s) failed"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    EXIT_FINAL=1
fi

# Create snapshot (if requested)
if [ "$SNAPSHOT" = true ]; then
  echo ""
  echo "╲ Creating Snapshot"
  echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

  bash lib/create-snapshot.sh || {
    log_error "Snapshot creation failed"
  }
fi

exit $EXIT_FINAL
