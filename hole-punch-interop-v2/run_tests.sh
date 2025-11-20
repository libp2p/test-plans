#!/bin/bash
# Main test orchestration script for hole punch interoperability tests

set -euo pipefail

# Defaults
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_FILTER="${TEST_FILTER:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
WORKER_COUNT="${WORKER_COUNT:-$(nproc 2>/dev/null || echo 4)}"
KIND="full"
CHECK_DEPS_ONLY=false
CREATE_SNAPSHOT=false

# Show help
show_help() {
    cat <<EOF
Hole Punch Interoperability Test Runner

Usage: $0 [options]

Options:
  --test-filter VALUE    Filter tests (pipe-separated substrings)
  --test-ignore VALUE    Ignore tests (pipe-separated substrings)
  --workers VALUE        Number of parallel workers (default: $(nproc 2>/dev/null || echo 4))
  --cache-dir VALUE      Cache directory (default: /srv/cache)
  --kind VALUE           Test kind: full, rust, go, etc. (default: auto-detect)
  --snapshot             Create test pass snapshot after completion
  --check-deps           Only check dependencies and exit
  --help                 Show this help message

Examples:
  $0 --cache-dir /srv/cache --workers 4
  $0 --test-filter "rust-v0.53" --workers 8
  $0 --test-ignore "tcp" --kind rust

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
        --kind) KIND="$2"; shift 2 ;;
        --snapshot) CREATE_SNAPSHOT=true; shift ;;
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

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Hole Punch Interoperability Test Suite                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Test Pass: hole-punch-${KIND}"
echo "Cache Dir: $CACHE_DIR"
echo "Workers: $WORKER_COUNT"
[ -n "$TEST_FILTER" ] && echo "Filter: $TEST_FILTER"
[ -n "$TEST_IGNORE" ] && echo "Ignore: $TEST_IGNORE"
echo ""

START_TIME=$(date +%s)

# Trap to ensure cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    bash scripts/stop-global-services.sh
}
trap cleanup EXIT

# 1. Check dependencies
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Checking dependencies..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! bash scripts/check-dependencies.sh; then
    echo "Dependency check failed. Please install missing dependencies."
    exit 1
fi

# 2. Build images
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building Docker images..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/build-images.sh "$TEST_FILTER"

# 3. Generate test matrix
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Generating test matrix..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/generate-tests.sh "$TEST_FILTER" "$TEST_IGNORE" "$IMPL_PATH"

# 4. Start global services
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting global services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/start-global-services.sh

# 5. Run tests in parallel
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running tests..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Read test matrix
test_count=$(yq eval '.metadata.totalTests' test-matrix.yaml)
echo "Total tests: $test_count"
echo ""

# Initialize results
mkdir -p logs
> results.yaml.tmp

# Run tests with parallel workers
run_test() {
    local index=$1
    local name=$(yq eval ".tests[$index].name" test-matrix.yaml)
    local dialer=$(yq eval ".tests[$index].dialer" test-matrix.yaml)
    local listener=$(yq eval ".tests[$index].listener" test-matrix.yaml)
    local transport=$(yq eval ".tests[$index].transport" test-matrix.yaml)

    echo "[$((index + 1))/$test_count] $name"

    start=$(date +%s)
    if bash scripts/run-single-test.sh "$name" "$dialer" "$listener" "$transport"; then
        status="pass"
        exit_code=0
    else
        status="fail"
        exit_code=1
    fi
    end=$(date +%s)
    duration=$((end - start))

    # Append to results (with locking to avoid race conditions)
    (
        flock -x 200
        cat >> results.yaml.tmp <<EOF
  - name: $name
    status: $status
    exitCode: $exit_code
    duration: ${duration}s
    dialer: $dialer
    listener: $listener
    transport: $transport
EOF
    ) 200>/tmp/results.lock

    return $exit_code
}

export -f run_test

# Run tests in parallel using xargs
seq 0 $((test_count - 1)) | xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}'

# 6. Collect results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Collecting results..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Count pass/fail
PASSED=$(grep -c "status: pass" results.yaml.tmp || echo 0)
FAILED=$(grep -c "status: fail" results.yaml.tmp || echo 0)

# Generate final results.yaml
cat > results.yaml <<EOF
metadata:
  testPass: hole-punch-${KIND}-$(date +%H%M%S-%d-%m-%Y)
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

cat results.yaml.tmp >> results.yaml
rm results.yaml.tmp

echo ""
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

# 7. Generate dashboard
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Generating results dashboard..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/generate-dashboard.sh

# 8. Create snapshot (optional)
if [ "${CREATE_SNAPSHOT:-false}" = "true" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Creating test pass snapshot..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash scripts/create-snapshot.sh
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAILED" -eq 0 ]; then
    echo "✓ All tests passed!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Results: results.yaml, results.md"
    [ -f results.html ] && echo "HTML Report: results.html"
    exit 0
else
    echo "✗ $FAILED test(s) failed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Results: results.yaml, results.md"
    [ -f results.html ] && echo "HTML Report: results.html"
    exit 1
fi
