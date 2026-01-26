#!/usr/bin/env bash

# JS-libp2p Echo Interoperability Tests
# Tests Echo protocol interoperability between js-libp2p (server) and py-libp2p (client)

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TYPE="js-libp2p-echo-interop"
TEST_ROOT="$SCRIPT_DIR"

# Set cache directory to local path
export CACHE_DIR="${SCRIPT_DIR}/.cache"

# Source common initialization
source "${SCRIPT_DIR}/../lib/lib-common-init.sh"

# Initialize common variables and cache directories
init_common_variables
init_cache_dirs

# Default configuration
DEFAULT_WORKERS="4"  # Fallback if nproc is not available
WORKERS="${WORKERS:-$DEFAULT_WORKERS}"
DEBUG="${DEBUG:-false}"
FORCE_IMAGE_REBUILD="${FORCE_IMAGE_REBUILD:-false}"
FORCE_MATRIX_REBUILD="${FORCE_MATRIX_REBUILD:-false}"
SNAPSHOT="${SNAPSHOT:-false}"
YES="${YES:-false}"

# Test filtering options
TEST_SELECT="${TEST_SELECT:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
IMPL_SELECT="${IMPL_SELECT:-}"
IMPL_IGNORE="${IMPL_IGNORE:-}"
TRANSPORT_SELECT="${TRANSPORT_SELECT:-}"
TRANSPORT_IGNORE="${TRANSPORT_IGNORE:-}"
SECURE_SELECT="${SECURE_SELECT:-}"
SECURE_IGNORE="${SECURE_IGNORE:-}"
MUXER_SELECT="${MUXER_SELECT:-}"
MUXER_IGNORE="${MUXER_IGNORE:-}"

# List options
LIST_TESTS="${LIST_TESTS:-false}"
LIST_IMAGES="${LIST_IMAGES:-false}"
SHOW_IGNORED="${SHOW_IGNORED:-false}"

# Dependency check
CHECK_DEPS="${CHECK_DEPS:-false}"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

JS-libp2p Echo Interoperability Tests
Tests Echo protocol interoperability between js-libp2p (server) and py-libp2p (client)

OPTIONS:
    --workers N                 Number of parallel test workers (default: 4)
    --debug                     Enable debug output in containers
    --force-image-rebuild       Force rebuild of all Docker images
    --force-matrix-rebuild      Force regeneration of test matrix
    --snapshot                  Create reproducible test snapshot
    --yes                       Skip confirmation prompts

FILTERING:
    --test-select PATTERN       Select tests matching pattern
    --test-ignore PATTERN       Ignore tests matching pattern
    --impl-select PATTERN       Select implementations matching pattern
    --impl-ignore PATTERN       Ignore implementations matching pattern
    --transport-select PATTERN  Select transports matching pattern
    --transport-ignore PATTERN  Ignore transports matching pattern
    --secure-select PATTERN     Select security protocols matching pattern
    --secure-ignore PATTERN     Ignore security protocols matching pattern
    --muxer-select PATTERN      Select muxers matching pattern
    --muxer-ignore PATTERN      Ignore muxers matching pattern

LISTING:
    --list-tests               List tests that would be run
    --list-images              List available implementations
    --show-ignored             Show ignored tests in addition to selected

UTILITIES:
    --check-deps               Check required dependencies
    --help                     Show this help message

EXAMPLES:
    # Run all tests
    $0

    # Run with more workers
    $0 --workers 8

    # Run only TCP transport tests
    $0 --transport-select "tcp"

    # Run with debug output
    $0 --debug

    # List what tests would run
    $0 --list-tests

    # Create snapshot for reproducibility
    $0 --snapshot

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        --force-image-rebuild)
            FORCE_IMAGE_REBUILD="true"
            shift
            ;;
        --force-matrix-rebuild)
            FORCE_MATRIX_REBUILD="true"
            shift
            ;;
        --snapshot)
            SNAPSHOT="true"
            shift
            ;;
        --yes)
            YES="true"
            shift
            ;;
        --test-select)
            TEST_SELECT="$2"
            shift 2
            ;;
        --test-ignore)
            TEST_IGNORE="$2"
            shift 2
            ;;
        --impl-select)
            IMPL_SELECT="$2"
            shift 2
            ;;
        --impl-ignore)
            IMPL_IGNORE="$2"
            shift 2
            ;;
        --transport-select)
            TRANSPORT_SELECT="$2"
            shift 2
            ;;
        --transport-ignore)
            TRANSPORT_IGNORE="$2"
            shift 2
            ;;
        --secure-select)
            SECURE_SELECT="$2"
            shift 2
            ;;
        --secure-ignore)
            SECURE_IGNORE="$2"
            shift 2
            ;;
        --muxer-select)
            MUXER_SELECT="$2"
            shift 2
            ;;
        --muxer-ignore)
            MUXER_IGNORE="$2"
            shift 2
            ;;
        --list-tests)
            LIST_TESTS="true"
            shift
            ;;
        --list-images)
            LIST_IMAGES="true"
            shift
            ;;
        --show-ignored)
            SHOW_IGNORED="true"
            shift
            ;;
        --check-deps)
            CHECK_DEPS="true"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Check dependencies if requested
if [[ "$CHECK_DEPS" == "true" ]]; then
    source "${SCRIPT_DIR}/../lib/check-dependencies.sh"
    exit 0
fi

# List images if requested
if [[ "$LIST_IMAGES" == "true" ]]; then
    echo "Available implementations:"
    if command -v yq >/dev/null 2>&1; then
        yq eval '.implementations[] | .id' "${SCRIPT_DIR}/images.yaml"
    else
        # Fallback parsing without yq
        grep -E "^\s*-\s*id:" "${SCRIPT_DIR}/images.yaml" | sed 's/.*id:\s*//' | sed 's/["s]*$//' | sed 's/^["s]*//'
    fi
    exit 0
fi

# Source required libraries
source "${SCRIPT_DIR}/../lib/lib-filter-engine.sh"
source "${SCRIPT_DIR}/../lib/lib-test-caching.sh"
source "${SCRIPT_DIR}/../lib/lib-image-building.sh"
source "${SCRIPT_DIR}/../lib/lib-global-services.sh"
source "${SCRIPT_DIR}/../lib/lib-output-formatting.sh"

# Generate test matrix
echo "Generating test matrix..."
source "${SCRIPT_DIR}/lib/generate-tests.sh"

# List tests if requested
if [[ "$LIST_TESTS" == "true" ]]; then
    if [[ "$SHOW_IGNORED" == "true" ]]; then
        echo "=== SELECTED TESTS ==="
        cat "$TEST_MATRIX_FILE" | yq eval '.selected[]' -
        echo ""
        echo "=== IGNORED TESTS ==="
        cat "$TEST_MATRIX_FILE" | yq eval '.ignored[]' -
    else
        cat "$TEST_MATRIX_FILE" | yq eval '.selected[]' -
    fi
    exit 0
fi

# Build required Docker images
echo "Building Docker images..."
source "${SCRIPT_DIR}/../lib/lib-image-building.sh"
build_images_from_yaml "${SCRIPT_DIR}/images.yaml"

# Start global services (Redis)
echo "Starting global services..."
start_global_services

# Run tests
echo "Running Echo interoperability tests..."
echo "Workers: $WORKERS"
echo "Debug: $DEBUG"

# Execute tests in parallel
cat "$TEST_MATRIX_FILE" | yq eval '.selected[]' - | \
    xargs -I {} -P "$WORKERS" bash -c "
        source '${SCRIPT_DIR}/lib/run-single-test.sh'
        run_single_test '{}'
    "

# Stop global services
echo "Stopping global services..."
stop_global_services

# Collect and format results
echo "Collecting results..."
source "${SCRIPT_DIR}/lib/generate-dashboard.sh"
generate_results_dashboard

# Create snapshot if requested
if [[ "$SNAPSHOT" == "true" ]]; then
    echo "Creating test snapshot..."
    source "${SCRIPT_DIR}/../lib/lib-snapshot-creation.sh"
    create_test_snapshot
fi

echo "Echo interoperability tests completed!"
echo "Results available in: $TEST_PASS_DIR"