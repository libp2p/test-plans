#!/bin/bash
# Main test orchestration script for transport interoperability tests

set -euo pipefail

# Defaults
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_FILTER="${TEST_FILTER:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
WORKER_COUNT="${WORKER_COUNT:-$(nproc 2>/dev/null || echo 4)}"
KIND="full"
CHECK_DEPS_ONLY=false
CREATE_SNAPSHOT=false
AUTO_YES=false

# Show help
show_help() {
    cat <<EOF
Transport Interoperability Test Runner

Usage: $0 [options]

Options:
  --test-filter VALUE    Filter tests (pipe-separated substrings)
  --test-ignore VALUE    Ignore tests (pipe-separated substrings)
  --workers VALUE        Number of parallel workers (default: $(nproc 2>/dev/null || echo 4))
  --cache-dir VALUE      Cache directory (default: /srv/cache)
  --kind VALUE           Test kind: full, rust, python, go, etc. (default: auto-detect)
  --type VALUE           Alias for --kind
  --snapshot             Create test pass snapshot after completion
  -y, --yes              Skip confirmation prompt and run tests immediately
  --check-deps           Only check dependencies and exit
  --help                 Show this help message

Examples:
  $0 --cache-dir /srv/cache --workers 4
  $0 --test-filter "rust-v0.53" --workers 8
  $0 --test-ignore "webrtc" --type rust
  $0 --type rust --test-filter "rust-v0.56"
  $0 --snapshot --workers 8

Dependencies:
  bash 4.0+, git 2.0+, docker 20.10+, yq 4.0+, wget, unzip
  Run with --check-deps to verify installation.
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test-filter) TEST_FILTER="$2"; shift 2 ;;
        --test-ignore) TEST_IGNORE="$2"; shift 2 ;;
        --workers) WORKER_COUNT="$2"; shift 2 ;;
        --cache-dir) CACHE_DIR="$2"; shift 2 ;;
        --kind|--type) KIND="$2"; shift 2 ;;  # Accept both --kind and --type
        --snapshot) CREATE_SNAPSHOT=true; shift ;;
        -y|--yes) AUTO_YES=true; shift ;;
        --check-deps) CHECK_DEPS_ONLY=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; echo ""; show_help; exit 1 ;;
    esac
done

# Change to script directory
cd "$(dirname "$0")"

# Check dependencies
if [ "$CHECK_DEPS_ONLY" = true ]; then
    bash scripts/check-dependencies.sh
    exit $?
fi

# Auto-detect kind from git changes if set to auto or empty
if [ -z "$KIND" ] || [ "$KIND" = "auto" ]; then
    if git rev-parse --git-dir > /dev/null 2>&1; then
        if git diff --name-only HEAD~1 2>/dev/null | grep -q 'impls/rust/'; then
            KIND="rust"
        elif git diff --name-only HEAD~1 2>/dev/null | grep -q 'impls/python/'; then
            KIND="python"
        elif git diff --name-only HEAD~1 2>/dev/null | grep -q 'impls/go/'; then
            KIND="go"
        else
            KIND="full"
        fi
    else
        KIND="full"
    fi
fi

# Determine impl path for test-selection.yaml loading
IMPL_PATH=""
if [ "$KIND" != "full" ]; then
    IMPL_PATH="impls/${KIND}"
fi

export CACHE_DIR

echo "                        ╔╦╦╗  ╔═╗"
echo "▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╠╣╚╦═╬╝╠═╗ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁"
echo "═══════════════════════ ║║║║║║║╔╣║║ ════════════════════════"
echo "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚╩╩═╣╔╩═╣╔╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "                            ╚╝  ╚╝"
echo ""

echo "╲ Transport Interoperability Test Suite"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Generate test pass name and folder
TEST_PASS_NAME="transport-interop-${KIND}-$(date +%H%M%S-%d-%m-%Y)"
TEST_PASS_DIR="$CACHE_DIR/test-passes/$TEST_PASS_NAME"

echo "Test Pass: $TEST_PASS_NAME"
echo "Cache Dir: $CACHE_DIR"
echo "Test Pass Dir: $TEST_PASS_DIR"
echo "Workers: $WORKER_COUNT"
[ -n "$TEST_FILTER" ] && echo "Filter: $TEST_FILTER"
[ -n "$TEST_IGNORE" ] && echo "Ignore: $TEST_IGNORE"
echo ""

# Create test pass folder structure
mkdir -p "$TEST_PASS_DIR"/{logs,docker-compose}

START_TIME=$(date +%s)

export TEST_PASS_NAME
export TEST_PASS_DIR

# 1. Check dependencies
echo "╲ Checking dependencies..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
if ! bash scripts/check-dependencies.sh; then
    echo "Dependency check failed. Please install missing dependencies."
    exit 1
fi

# Read and export the docker compose command detected by check-dependencies.sh
if [ -f /tmp/docker-compose-cmd.txt ]; then
    export DOCKER_COMPOSE_CMD=$(cat /tmp/docker-compose-cmd.txt)
    echo "Using: $DOCKER_COMPOSE_CMD"
else
    echo "Error: Could not determine docker compose command"
    exit 1
fi

# 2. Generate test matrix FIRST (before building images)
echo ""
echo "╲ Generating test matrix..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ bash scripts/generate-tests.sh \"$TEST_FILTER\" \"$TEST_IGNORE\" \"$IMPL_PATH\""
bash scripts/generate-tests.sh "$TEST_FILTER" "$TEST_IGNORE" "$IMPL_PATH"

# 3. Extract unique implementations from test matrix and build only those
echo ""
echo "╲ Building Docker images..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Get unique implementations from test matrix (dialer + listener)
REQUIRED_IMPLS=$(mktemp)
yq eval '.tests[].dialer' "$TEST_PASS_DIR/test-matrix.yaml" | sort -u > "$REQUIRED_IMPLS"
yq eval '.tests[].listener' "$TEST_PASS_DIR/test-matrix.yaml" | sort -u >> "$REQUIRED_IMPLS"
sort -u "$REQUIRED_IMPLS" -o "$REQUIRED_IMPLS"

# Also add base images for any browser-type implementations
REQUIRED_IMPLS_WITH_DEPS=$(mktemp)
cp "$REQUIRED_IMPLS" "$REQUIRED_IMPLS_WITH_DEPS"

while IFS= read -r impl_id; do
    # Check if this is a browser-type implementation
    source_type=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .source.type" impls.yaml)
    if [ "$source_type" = "browser" ]; then
        # Add its base image as a dependency
        base_image=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .source.baseImage" impls.yaml)
        echo "$base_image" >> "$REQUIRED_IMPLS_WITH_DEPS"
    fi
done < "$REQUIRED_IMPLS"

# Sort and deduplicate
sort -u "$REQUIRED_IMPLS_WITH_DEPS" -o "$REQUIRED_IMPLS_WITH_DEPS"

IMPL_COUNT=$(wc -l < "$REQUIRED_IMPLS_WITH_DEPS")
echo "→ Building $IMPL_COUNT required implementations (including base images)"
echo ""

# Build each required implementation using pipe-separated list
IMPL_FILTER=$(cat "$REQUIRED_IMPLS_WITH_DEPS" | paste -sd'|' -)
echo "→ bash scripts/build-images.sh \"$IMPL_FILTER\""
bash scripts/build-images.sh "$IMPL_FILTER"

rm -f "$REQUIRED_IMPLS" "$REQUIRED_IMPLS_WITH_DEPS"

# Display test list and prompt for confirmation
echo ""
echo "╲ Selected tests:"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Read test matrix
test_count=$(yq eval '.metadata.totalTests' "$TEST_PASS_DIR/test-matrix.yaml")
ignored_count=$(yq eval '.metadata.ignoredTests' "$TEST_PASS_DIR/test-matrix.yaml")

# Display active tests
for ((i=0; i<test_count; i++)); do
    test_name=$(yq eval ".tests[$i].name" "$TEST_PASS_DIR/test-matrix.yaml")
    echo "  ✓ $test_name"
done

# Display ignored tests
if [ "$ignored_count" -gt 0 ]; then
    echo ""
    echo "Ignored tests:"
    for ((i=0; i<ignored_count; i++)); do
        test_name=$(yq eval ".ignoredTests[$i].name" "$TEST_PASS_DIR/test-matrix.yaml")
        echo "  ✗ $test_name [ignored]"
    done
fi

echo ""
echo "Total: $test_count tests to execute, $ignored_count ignored"

# Prompt user for confirmation (unless -y flag was set)
if [ "$AUTO_YES" = false ]; then
    read -p "Execute $test_count tests? (Y/n): " response
    response=${response:-Y}  # Default to Y if user just presses enter

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Test execution cancelled."
        exit 0
    fi
fi

# 4. Run tests in parallel
echo ""
echo "╲ Running tests..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Read test matrix and export test_count for use in subshells
test_count=$(yq eval '.metadata.totalTests' "$TEST_PASS_DIR/test-matrix.yaml")
export test_count

# Initialize results
> "$TEST_PASS_DIR/results.yaml.tmp"

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
    if bash scripts/run-single-test.sh "$name" "$dialer" "$listener" "$transport" "$secure" "$muxer"; then
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

    # Append to results (with locking to avoid race conditions)
    (
        flock -x 200
        cat >> "$TEST_PASS_DIR/results.yaml.tmp" <<EOF
  - name: $name
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
            echo "    handshakePlusOneRTTMs: $handshake_ms" >> "$TEST_PASS_DIR/results.yaml.tmp"
        fi
        if [ -n "$ping_ms" ]; then
            echo "    pingRTTMs: $ping_ms" >> "$TEST_PASS_DIR/results.yaml.tmp"
        fi
    ) 200>/tmp/results.lock

    return $exit_code
}

export -f run_test

# Run tests in parallel using xargs
seq 0 $((test_count - 1)) | xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}'

# 5. Collect results
echo ""
echo "╲ Collecting results..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Count pass/fail
# grep -c outputs "0" and exits with status 1 when count is 0
# Using || true to avoid the || echo 0 adding an extra 0
PASSED=$(grep -c "status: pass" "$TEST_PASS_DIR/results.yaml.tmp" || true)
FAILED=$(grep -c "status: fail" "$TEST_PASS_DIR/results.yaml.tmp" || true)

# Handle empty results (when grep finds nothing, it outputs nothing with || true)
PASSED=${PASSED:-0}
FAILED=${FAILED:-0}

# Generate final results.yaml
cat > "$TEST_PASS_DIR/results.yaml" <<EOF
metadata:
  testPass: $TEST_PASS_NAME
  startedAt: $(date -d @$START_TIME -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -r $START_TIME -u +%Y-%m-%dT%H:%M:%SZ)
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

cat "$TEST_PASS_DIR/results.yaml.tmp" >> "$TEST_PASS_DIR/results.yaml"
rm "$TEST_PASS_DIR/results.yaml.tmp"

echo "Results:"
echo "  Total: $test_count"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo ""

# Display execution time
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))
printf "Total time: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS

# 6. Generate dashboard
echo ""
echo "╲ Generating results dashboard..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ bash scripts/generate-dashboard.sh"
bash scripts/generate-dashboard.sh

# 7. Create snapshot (optional)
if [ "$CREATE_SNAPSHOT" = true ]; then
    echo ""
    echo "╲ Creating test pass snapshot..."
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "→ bash scripts/create-snapshot.sh"
    bash scripts/create-snapshot.sh
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "╲ ✓ All tests passed!"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "Results: results.yaml, results.md"
    [ -f results.html ] && echo "HTML Report: results.html"
    EXIT_FINAL=0
else
    echo "╲ ✗ $FAILED test(s) failed"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo ""
    echo "Results: results.yaml, results.md"
    [ -f results.html ] && echo "HTML Report: results.html"
    echo "Logs: logs/ directory"
    EXIT_FINAL=1
fi

exit $EXIT_FINAL
