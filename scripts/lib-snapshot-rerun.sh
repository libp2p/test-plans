#!/bin/bash
# Re-run script generator for test snapshots
# Generates complete re-run.sh scripts with full option support

# Main function: Generate complete re-run.sh script
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: test_type - Type of test (transport|hole-punch|perf)
#   $3: test_pass_name - Name of test pass
#   $4: original_options_array_name - Name of associative array with original options
# Usage:
#   declare -A orig_opts
#   orig_opts[test_select]="~rust"
#   orig_opts[workers]="8"
#   generate_rerun_script "$snapshot_dir" "transport" "$test_pass" orig_opts
generate_rerun_script() {
    local snapshot_dir="$1"
    local test_type="$2"
    local test_pass_name="$3"
    local -n orig_opts_ref=$4

    local rerun_file="$snapshot_dir/re-run.sh"

    # Start the script
    cat > "$rerun_file" <<'RERUN_HEADER'
#!/bin/bash
# Re-run script for test snapshot
# Generated automatically - supports same options as run_tests.sh

set -euo pipefail

RERUN_HEADER

    # Generate default values
    _generate_default_values "$rerun_file" "$test_type" orig_opts_ref

    # Generate help function
    _generate_help_function "$rerun_file" "$test_type" "$test_pass_name"

    # Generate argument parser
    _generate_argument_parser "$rerun_file" "$test_type"

    # Generate main execution
    _generate_main_execution "$rerun_file" "$test_type"

    # Make executable
    chmod +x "$rerun_file"

    return 0
}

# Internal: Generate default values section
_generate_default_values() {
    local rerun_file="$1"
    local test_type="$2"
    local -n opt_vals_ref=$3

    cat >> "$rerun_file" <<DEFAULTS
# Default values from original run
TEST_SELECT="\${TEST_SELECT:-${opt_vals_ref[test_select]:-}}"
TEST_IGNORE="\${TEST_IGNORE:-${opt_vals_ref[test_ignore]:-}}"
WORKERS="\${WORKERS:-${opt_vals_ref[workers]:-\$(nproc 2>/dev/null || echo 4)}}"
DEBUG="\${DEBUG:-${opt_vals_ref[debug]:-false}}"
FORCE_MATRIX_REBUILD=false
FORCE_IMAGE_REBUILD=false
AUTO_YES=false
CHECK_DEPS_ONLY=false
LIST_IMPLS=false
LIST_TESTS=false

DEFAULTS

    # Add test-type-specific defaults
    case "$test_type" in
        hole-punch)
            cat >> "$rerun_file" <<'HPDEFAULTS'
RELAY_SELECT="${RELAY_SELECT:-}"
RELAY_IGNORE="${RELAY_IGNORE:-}"
ROUTER_SELECT="${ROUTER_SELECT:-}"
ROUTER_IGNORE="${ROUTER_IGNORE:-}"
LIST_RELAYS=false
LIST_ROUTERS=false

HPDEFAULTS
            ;;
        perf)
            cat >> "$rerun_file" <<PERFDEFAULTS
BASELINE_SELECT="\${BASELINE_SELECT:-${opt_vals_ref[baseline_select]:-}}"
BASELINE_IGNORE="\${BASELINE_IGNORE:-${opt_vals_ref[baseline_ignore]:-}}"
ITERATIONS="\${ITERATIONS:-${opt_vals_ref[iterations]:-10}}"
UPLOAD_BYTES="\${UPLOAD_BYTES:-${opt_vals_ref[upload_bytes]:-1073741824}}"
DOWNLOAD_BYTES="\${DOWNLOAD_BYTES:-${opt_vals_ref[download_bytes]:-1073741824}}"
DURATION_PER_ITERATION="\${DURATION_PER_ITERATION:-20}"
LATENCY_ITERATIONS="\${LATENCY_ITERATIONS:-100}"

PERFDEFAULTS
            ;;
    esac
}

# Internal: Generate help function
_generate_help_function() {
    local rerun_file="$1"
    local test_type="$2"
    local test_pass_name="$3"

    # Get test type display name
    local test_name
    case "$test_type" in
        transport) test_name="Transport Interoperability" ;;
        hole-punch) test_name="Hole Punch Interoperability" ;;
        perf) test_name="Performance Benchmark" ;;
    esac

    cat >> "$rerun_file" <<HELPSTART
# Show help
show_help() {
    cat <<HELP
Re-run $test_name Test Snapshot

Test Pass: $test_pass_name

Usage: \\\$0 [options]

Common Options:
  --test-select VALUE        Select tests (pipe-separated, supports ~alias)
  --test-ignore VALUE        Ignore tests (pipe-separated, supports !inversion)
  --workers VALUE            Number of parallel workers (default: \$WORKERS)
  --debug                    Enable debug mode in test containers
  --force-matrix-rebuild     Force test matrix regeneration
  --force-image-rebuild      Force Docker image rebuilds
  -y, --yes                  Skip confirmation prompts
  --check-deps               Check dependencies and exit
  --list-impls               List implementations and exit
  --list-tests               List tests and exit
  --help, -h                 Show this help message

HELPSTART

    # Add test-type-specific options
    case "$test_type" in
        hole-punch)
            cat >> "$rerun_file" <<'HPHELP'
Hole-Punch Specific Options:
  --relay-select VALUE       Select relays
  --relay-ignore VALUE       Ignore relays
  --router-select VALUE      Select routers
  --router-ignore VALUE      Ignore routers
  --list-relays              List relays and exit
  --list-routers             List routers and exit

HPHELP
            ;;
        perf)
            cat >> "$rerun_file" <<'PERFHELP'
Perf Specific Options:
  --baseline-select VALUE    Select baseline tests
  --baseline-ignore VALUE    Ignore baseline tests
  --iterations VALUE         Number of iterations per test (default: 10)
  --upload-bytes VALUE       Bytes to upload per test
  --download-bytes VALUE     Bytes to download per test

PERFHELP
            ;;
    esac

    cat >> "$rerun_file" <<'HELPEND'
Examples:
  # Re-run with original settings
  $0

  # Re-run with different filter
  $0 --test-select '~rust' --workers 4

  # Force rebuild and re-run
  $0 --force-image-rebuild --force-matrix-rebuild

  # List tests without running
  $0 --test-select '~go' --list-tests

Description:
  This script re-runs a snapshot of a test pass. It supports the same
  filtering and configuration options as the original run_tests.sh script.

  By default, uses cached Docker images and the original test matrix.
  Use --force-image-rebuild to rebuild images from source.
  Use --force-matrix-rebuild or provide filters to regenerate the test matrix.

Dependencies:
  bash 4.0+, docker 20.10+, yq 4.0+, wget, unzip
HELP
}

HELPEND
}

# Internal: Generate argument parser
_generate_argument_parser() {
    local rerun_file="$1"
    local test_type="$2"

    cat >> "$rerun_file" <<'ARGPARSE'
# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test-select) TEST_SELECT="$2"; shift 2 ;;
        --test-ignore) TEST_IGNORE="$2"; shift 2 ;;
        --workers) WORKERS="$2"; shift 2 ;;
        --debug) DEBUG=true; shift ;;
        --force-matrix-rebuild) FORCE_MATRIX_REBUILD=true; shift ;;
        --force-image-rebuild) FORCE_IMAGE_REBUILD=true; shift ;;
        -y|--yes) AUTO_YES=true; shift ;;
        --check-deps) CHECK_DEPS_ONLY=true; shift ;;
        --list-impls) LIST_IMPLS=true; shift ;;
        --list-tests) LIST_TESTS=true; shift ;;
ARGPARSE

    # Add test-type-specific argument parsing
    case "$test_type" in
        hole-punch)
            cat >> "$rerun_file" <<'HPARGS'
        --relay-select) RELAY_SELECT="$2"; shift 2 ;;
        --relay-ignore) RELAY_IGNORE="$2"; shift 2 ;;
        --router-select) ROUTER_SELECT="$2"; shift 2 ;;
        --router-ignore) ROUTER_IGNORE="$2"; shift 2 ;;
        --list-relays) LIST_RELAYS=true; shift ;;
        --list-routers) LIST_ROUTERS=true; shift ;;
HPARGS
            ;;
        perf)
            cat >> "$rerun_file" <<'PERFARGS'
        --baseline-select) BASELINE_SELECT="$2"; shift 2 ;;
        --baseline-ignore) BASELINE_IGNORE="$2"; shift 2 ;;
        --iterations) ITERATIONS="$2"; shift 2 ;;
        --upload-bytes) UPLOAD_BYTES="$2"; shift 2 ;;
        --download-bytes) DOWNLOAD_BYTES="$2"; shift 2 ;;
PERFARGS
            ;;
    esac

    cat >> "$rerun_file" <<'ARGPARSEEND'
        --help|-h) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; echo ""; show_help; exit 1 ;;
    esac
done

ARGPARSEEND
}

# Internal: Generate main execution section
_generate_main_execution() {
    local rerun_file="$1"
    local test_type="$2"

    # Common setup
    cat >> "$rerun_file" <<'SETUP'
# Change to snapshot directory
cd "$(dirname "$0")"

# Display banner
echo ""
echo "                        ╔╦╦╗  ╔═╗"
echo "▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╠╣╚╦═╬╝╠═╗ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁"
echo "═══════════════════════ ║║║║║║║╔╣║║ ════════════════════════"
echo "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚╩╩═╣╔╩═╣╔╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "                            ╚╝  ╚╝"
echo ""

echo "╲ Re-running test pass from snapshot..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Validate snapshot
if [ ! -f impls.yaml ] || [ ! -f test-matrix.yaml ]; then
    echo "✗ Error: Required files missing. Not a valid snapshot."
    exit 1
fi

# Set cache dir to snapshot location
export CACHE_DIR="$(pwd)"
export TEST_PASS_DIR="$(pwd)/re-runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEST_PASS_DIR"/{logs,docker-compose,results,baseline}

# Display where results will be written
RERUN_TIMESTAMP=$(basename "$TEST_PASS_DIR")
echo "→ Re-run results: re-runs/$RERUN_TIMESTAMP/"
echo ""

SETUP

    # Handle check-deps
    cat >> "$rerun_file" <<'CHECKDEPS'
# Check dependencies
if [ "$CHECK_DEPS_ONLY" = true ]; then
    bash scripts/../scripts/check-dependencies.sh
    exit $?
fi

CHECKDEPS

    # Handle list commands
    _generate_list_commands "$rerun_file" "$test_type"

    # Load GitHub sources
    cat >> "$rerun_file" <<'LOADSOURCES'
# Source the GitHub snapshot loading code from lib-github-snapshots.sh
LOADSOURCES

    # Embed the source loading code
    generate_source_loading_code "$test_type" >> "$rerun_file"

    cat >> "$rerun_file" <<'CALLLOAD'

# Load sources
load_github_sources

CALLLOAD

    # Generate image handling
    _generate_image_handling "$rerun_file" "$test_type"

    # Generate matrix regeneration logic
    _generate_matrix_regeneration "$rerun_file" "$test_type"

    # Generate test execution
    _generate_test_execution "$rerun_file" "$test_type"

    # Generate results collection
    _generate_results_collection "$rerun_file" "$test_type"

    # Final message
    cat >> "$rerun_file" <<'FINAL'

echo ""
echo "✓ Re-run complete!"
echo "→ Results: $TEST_PASS_DIR/results.md"
FINAL
}

# Internal: Generate list commands (--list-impls, --list-tests, etc.)
_generate_list_commands() {
    local rerun_file="$1"
    local test_type="$2"

    cat >> "$rerun_file" <<'LISTIMPLS'
# List implementations
if [ "$LIST_IMPLS" = true ]; then
    echo "╲ Available Implementations"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    yq eval '.implementations[].id' impls.yaml | sed 's/^/→ /'
    echo ""
    exit 0
fi

LISTIMPLS

    # Add test-type-specific list commands
    if [ "$test_type" = "hole-punch" ]; then
        cat >> "$rerun_file" <<'HPLIST'
# List relays
if [ "$LIST_RELAYS" = true ]; then
    echo "╲ Available Relays"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    yq eval '.relays[].id' impls.yaml | sed 's/^/→ /'
    echo ""
    exit 0
fi

# List routers
if [ "$LIST_ROUTERS" = true ]; then
    echo "╲ Available Routers"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    yq eval '.routers[].id' impls.yaml | sed 's/^/→ /'
    echo ""
    exit 0
fi

HPLIST
    fi

    # List tests
    cat >> "$rerun_file" <<'LISTTESTS'
# List tests
if [ "$LIST_TESTS" = true ]; then
    test_count=$(yq eval '.tests | length' test-matrix.yaml)
    echo "╲ Selected Tests ($test_count tests)"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    yq eval '.tests[].name' test-matrix.yaml | sed 's/^/→ /'
    echo ""
    exit 0
fi

LISTTESTS
}

# Internal: Generate image handling section
_generate_image_handling() {
    local rerun_file="$1"
    local test_type="$2"

    cat >> "$rerun_file" <<'IMAGEHANDLE'
echo ""
echo "╲ Docker Images"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

if [ "$FORCE_IMAGE_REBUILD" = true ]; then
    echo "→ Force rebuild enabled - building images from source..."

    # Get list of implementations from test matrix
    REQUIRED_IMPLS=$(mktemp)
    yq eval '.tests[].dialer' test-matrix.yaml | sort -u > "$REQUIRED_IMPLS"
    yq eval '.tests[].listener' test-matrix.yaml | sort -u >> "$REQUIRED_IMPLS"
    sort -u "$REQUIRED_IMPLS" -o "$REQUIRED_IMPLS"

    IMPL_FILTER=$(cat "$REQUIRED_IMPLS" | paste -sd'|' -)
    rm "$REQUIRED_IMPLS"

    bash scripts/build-images.sh "$IMPL_FILTER" "$DEBUG"

elif [ -d docker-images ] && [ "$(ls -A docker-images 2>/dev/null)" ]; then
    echo "→ Loading Docker images from snapshot..."

    for image_file in docker-images/*.tar.gz; do
        [ ! -f "$image_file" ] && continue
        echo "  → Loading $(basename "$image_file")..."
        gunzip -c "$image_file" | docker load
    done

    echo "  ✓ Loaded Docker images"

else
    echo "→ No cached images - building from source..."

    REQUIRED_IMPLS=$(mktemp)
    yq eval '.tests[].dialer' test-matrix.yaml | sort -u > "$REQUIRED_IMPLS"
    yq eval '.tests[].listener' test-matrix.yaml | sort -u >> "$REQUIRED_IMPLS"
    sort -u "$REQUIRED_IMPLS" -o "$REQUIRED_IMPLS"

    IMPL_FILTER=$(cat "$REQUIRED_IMPLS" | paste -sd'|' -)
    rm "$REQUIRED_IMPLS"

    bash scripts/build-images.sh "$IMPL_FILTER" "$DEBUG"
fi

IMAGEHANDLE
}

# Internal: Generate matrix regeneration logic
_generate_matrix_regeneration() {
    local rerun_file="$1"
    local test_type="$2"

    cat >> "$rerun_file" <<'MATRIXREGEN'
echo ""
echo "╲ Test Matrix"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Determine if we need to regenerate matrix
NEED_REGEN=false

if [ "$FORCE_MATRIX_REBUILD" = true ]; then
    echo "→ Force matrix rebuild enabled"
    NEED_REGEN=true
fi

# Check if filters were provided (different from snapshot)
if [ -n "$TEST_SELECT" ] || [ -n "$TEST_IGNORE" ]; then
    echo "→ Test filters provided - will regenerate matrix"
    NEED_REGEN=true
fi

MATRIXREGEN

    # Add test-type-specific filter checks
    case "$test_type" in
        hole-punch)
            cat >> "$rerun_file" <<'HPMATRIX'
if [ -n "$RELAY_SELECT" ] || [ -n "$RELAY_IGNORE" ] || \
   [ -n "$ROUTER_SELECT" ] || [ -n "$ROUTER_IGNORE" ]; then
    echo "→ Relay/router filters provided - will regenerate matrix"
    NEED_REGEN=true
fi

HPMATRIX
            ;;
        perf)
            cat >> "$rerun_file" <<'PERFMATRIX'
if [ -n "$BASELINE_SELECT" ] || [ -n "$BASELINE_IGNORE" ]; then
    echo "→ Baseline filters provided - will regenerate matrix"
    NEED_REGEN=true
fi

PERFMATRIX
            ;;
    esac

    cat >> "$rerun_file" <<'MATRIXDO'
if [ "$NEED_REGEN" = true ]; then
    echo "→ Regenerating test matrix..."
    export TEST_SELECT TEST_IGNORE DEBUG FORCE_MATRIX_REBUILD TEST_PASS_DIR CACHE_DIR
MATRIXDO

    # Export test-type-specific variables
    case "$test_type" in
        hole-punch)
            cat >> "$rerun_file" <<'HPEXPORT'
    export RELAY_SELECT RELAY_IGNORE ROUTER_SELECT ROUTER_IGNORE
HPEXPORT
            ;;
        perf)
            cat >> "$rerun_file" <<'PERFEXPORT'
    export BASELINE_SELECT BASELINE_IGNORE ITERATIONS UPLOAD_BYTES DOWNLOAD_BYTES
PERFEXPORT
            ;;
    esac

    # Generate the matrix based on test type
    case "$test_type" in
        hole-punch)
            cat >> "$rerun_file" <<'HPGEN'
    bash scripts/generate-tests.sh "$TEST_SELECT" "$TEST_IGNORE" "$RELAY_SELECT" "$RELAY_IGNORE" "$ROUTER_SELECT" "$ROUTER_IGNORE" "$DEBUG" "false"
HPGEN
            ;;
        perf)
            cat >> "$rerun_file" <<'PERFGEN'
    bash scripts/generate-tests.sh
PERFGEN
            ;;
        *)
            cat >> "$rerun_file" <<'TRANSGEN'
    bash scripts/generate-tests.sh "$TEST_SELECT" "$TEST_IGNORE" "$DEBUG" "false"
TRANSGEN
            ;;
    esac

    cat >> "$rerun_file" <<'MATRIXEND'
    cp "$TEST_PASS_DIR/test-matrix.yaml" test-matrix.yaml
    echo "  ✓ Test matrix regenerated"
else
    echo "→ Using snapshot test matrix"
fi

MATRIXEND
}

# Internal: Generate test execution section
_generate_test_execution() {
    local rerun_file="$1"
    local test_type="$2"

    # Start global services for hole-punch
    if [ "$test_type" = "hole-punch" ]; then
        cat >> "$rerun_file" <<'HPSERVICES'
echo ""
echo "╲ Starting Global Services"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
bash scripts/start-global-services.sh

HPSERVICES
    fi

    # Common test execution
    cat >> "$rerun_file" <<'TESTEXEC'
echo ""
echo "╲ Running Tests"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

test_count=$(yq eval '.tests | length' test-matrix.yaml)
echo "→ Running $test_count tests with $WORKERS workers..."

# Export variables for test execution
export TEST_PASS_DIR CACHE_DIR DEBUG

TESTEXEC

    # Initialize results file
    cat >> "$rerun_file" <<'INITRESULTS'
# Initialize results file
> "$TEST_PASS_DIR/results.yaml.tmp"

INITRESULTS

    # Generate test-type-specific run_test function
    case "$test_type" in
        transport|hole-punch)
            cat >> "$rerun_file" <<'TRANSPORTEXEC'
# Define test execution function
run_test() {
    local index=$1

    # Extract test details from matrix
    local name=$(yq eval ".tests[$index].name" test-matrix.yaml)
    local dialer=$(yq eval ".tests[$index].dialer" test-matrix.yaml)
    local listener=$(yq eval ".tests[$index].listener" test-matrix.yaml)
    local transport=$(yq eval ".tests[$index].transport" test-matrix.yaml)
    local secure=$(yq eval ".tests[$index].secureChannel" test-matrix.yaml)
    local muxer=$(yq eval ".tests[$index].muxer" test-matrix.yaml)

    # Run test and capture result
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

    # Append to results with file locking
    (
        flock -x 200
        cat >> "$TEST_PASS_DIR/results.yaml.tmp" <<RESULT
  - name: $name
    status: $status
    exitCode: $exit_code
    duration: ${duration}s
    dialer: $dialer
    listener: $listener
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
RESULT
    ) 200>/tmp/results.lock

    return $exit_code
}

export -f run_test

# Run tests in parallel
seq 0 $((test_count - 1)) | xargs -P "$WORKERS" -I {} bash -c 'run_test {}' || true

TRANSPORTEXEC
            ;;
        perf)
            cat >> "$rerun_file" <<'PERFEXEC'
# Define test execution function
run_test() {
    local index=$1
    local test_type="main"

    # Extract test name
    local name=$(yq eval ".tests[$index].name" test-matrix.yaml)

    # Run test and capture result
    if bash scripts/run-single-test.sh "$index" "$test_type"; then
        status="pass"
        exit_code=0
    else
        status="fail"
        exit_code=1
    fi

    # Append to results with file locking
    (
        flock -x 200
        cat >> "$TEST_PASS_DIR/results.yaml.tmp" <<RESULT
  - name: $name
    status: $status
    exitCode: $exit_code
RESULT
    ) 200>/tmp/results.lock

    return $exit_code
}

export -f run_test

# Run tests in parallel
seq 0 $((test_count - 1)) | xargs -P "$WORKERS" -I {} bash -c 'run_test {}' || true

PERFEXEC
            ;;
    esac

    # Stop global services for hole-punch
    if [ "$test_type" = "hole-punch" ]; then
        cat >> "$rerun_file" <<'HPSTOP'
echo ""
echo "╲ Stopping Global Services"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
bash scripts/stop-global-services.sh

HPSTOP
    fi
}

# Internal: Generate results collection section
_generate_results_collection() {
    local rerun_file="$1"
    local test_type="$2"

    cat >> "$rerun_file" <<'RESULTS'
echo ""
echo "╲ Collecting Results"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Aggregate results from results.yaml.tmp
if [ -f "$TEST_PASS_DIR/results.yaml.tmp" ] && [ -s "$TEST_PASS_DIR/results.yaml.tmp" ]; then
    # Count results (grep -c returns count, never fails on valid file)
    PASSED=$(grep -c "status: pass" "$TEST_PASS_DIR/results.yaml.tmp" || echo "0")
    FAILED=$(grep -c "status: fail" "$TEST_PASS_DIR/results.yaml.tmp" || echo "0")
    # Ensure numeric values
    PASSED=${PASSED:-0}
    FAILED=${FAILED:-0}
    TOTAL=$((PASSED + FAILED))

    # Generate final results.yaml
    cat > "$TEST_PASS_DIR/results.yaml" <<YAML
metadata:
  testPass: $(basename "$TEST_PASS_DIR")
  startedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: $WORKERS

summary:
  total: $TOTAL
  passed: $PASSED
  failed: $FAILED

tests:
YAML

    # Append test results
    cat "$TEST_PASS_DIR/results.yaml.tmp" >> "$TEST_PASS_DIR/results.yaml"
    rm "$TEST_PASS_DIR/results.yaml.tmp"

    echo "  ✓ Aggregated $TOTAL test results"
else
    echo "  ⚠ No results file found"
    PASSED=0
    FAILED=0
    TOTAL=0
fi

# Generate dashboard
if [ -f scripts/generate-dashboard.sh ]; then
    bash scripts/generate-dashboard.sh
    echo "  ✓ Generated results dashboard"
fi

# Final counts (already calculated above)
PASSED=${PASSED:-0}
FAILED=${FAILED:-0}
TOTAL=${TOTAL:-0}

echo ""
echo "✓ Re-run complete!"
echo "→ Results: \$PASSED/\$TOTAL passed, \$FAILED failed"
echo "→ Location: \$TEST_PASS_DIR/"
echo "→ Dashboard: \$TEST_PASS_DIR/results.md"

RESULTS

    # Add perf-specific box plot generation
    if [ "$test_type" = "perf" ]; then
        cat >> "$rerun_file" <<'PERFBOXPLOT'
# Generate box plots for perf tests
if [ -f scripts/generate-boxplot.sh ]; then
    bash scripts/generate-boxplot.sh
    echo "  ✓ Generated box plots"
fi

PERFBOXPLOT
    fi
}

# Helper: Get test type display name
get_test_type_display_name() {
    local test_type="$1"

    case "$test_type" in
        transport) echo "Transport Interoperability" ;;
        hole-punch) echo "Hole Punch Interoperability" ;;
        perf) echo "Performance Benchmark" ;;
        *) echo "Test" ;;
    esac
}

# Helper: Check if re-run script exists and is valid
validate_rerun_script() {
    local snapshot_dir="$1"

    if [ ! -f "$snapshot_dir/re-run.sh" ]; then
        echo "✗ re-run.sh not found" >&2
        return 1
    fi

    if [ ! -x "$snapshot_dir/re-run.sh" ]; then
        echo "✗ re-run.sh not executable" >&2
        return 1
    fi

    # Basic syntax check
    if ! bash -n "$snapshot_dir/re-run.sh" 2>/dev/null; then
        echo "✗ re-run.sh has syntax errors" >&2
        return 1
    fi

    return 0
}
