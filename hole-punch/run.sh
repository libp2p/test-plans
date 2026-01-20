#!/bin/bash

# run in strict failure mode
set -euo pipefail

#                                 ╔╦╦╗  ╔═╗
# ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╠╣╚╦═╬╝╠═╗ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
# ═══════════════════════════════ ║║║║║║║╔╣║║ ═════════════════════════════════
# ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚╩╩═╣╔╩═╣╔╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
#                                     ╚╝  ╚╝

# =============================================================================
# STEP 1: BOOTSTRAP: Load inputs.yaml BEFORE setting SCRIPT_LIB_DIR
# -----------------------------------------------------------------------------
# This allows for the re-creation of the environment and command line arguments
# from a previous test run. If the inputs.yaml file doesn't exist, then this
# script will run from a default environment. Any command line arguments passed
# will override any command line arguments loaded from inputs.yaml, however the
# environment variables in inputs.yaml will override the ones initialized in
# the shell executing this script.
# =============================================================================

# Capture original arguments for inputs.yaml generation
ORIGINAL_ARGS=("$@")

# Change to script directory
cd "$(dirname "$0")"

# Loads and exports the environment variables from the inputs yaml file
load_inputs_yaml_inline() {
  local inputs_file="${1:-inputs.yaml}"

  # Look for the inputs file if it exists
  if [ ! -f "${inputs_file}" ]; then
    return 1
  fi

  echo "→ Loading configuration from ${inputs_file}"

  # Load and export the environment variables from the inputs file
  while IFS='=' read -r key value; do
    if [ -n "${key}" ] && [ -n "${value}" ]; then
      export "${key}"="${value}"
    fi
  done < <(yq eval '.environmentVariables | to_entries | .[] | .key + "=" + .value' "${inputs_file}" 2>/dev/null)

  return 0
}

# Loads the command line arguments from the inputs yaml file
get_yaml_args_inline() {
  local inputs_file="${1:-inputs.yaml}"
  if [ ! -f "${inputs_file}" ]; then
    return 1
  fi
  yq eval '.commandLineArgs[]' "${inputs_file}" 2>/dev/null || true
}

# Process inputs.yaml if it exists
if [ -f "inputs.yaml" ]; then
  load_inputs_yaml_inline "inputs.yaml"
  readarray -t YAML_ARGS < <(get_yaml_args_inline "inputs.yaml")
else
  YAML_ARGS=()
fi

# Append actual command-line args (these override inputs.yaml)
CMD_LINE_ARGS=("${YAML_ARGS[@]}" "$@")

# Set positional parameters to merged args
set -- "${CMD_LINE_ARGS[@]}"

# NOTE: this test can be run and later re-run. When run initially, the
# SCRIPT_DIR is something like `<repo root>/hole-punch/lib` and the
# SCRIPT_LIB_DIR is then `${SCRIPT_DIR}/../../lib`. The SCRIPT_DIR points to
# where the hole-punch-specific test scripts are located and the SCRIPT_LIB_DIR is
# where the scripts that are common to all tests are located. An inputs.yaml
# file is generated to capture these values for re-running the same test later.
# When re-running a test from a snapshot, all scripts are located in the same
# folder: `<snapshot root>/lib` so the inputs.yaml file is used to initialize
# the environment variables so that all scripts load properly.

# Set SCRIPT_LIB_DIR after inputs.yaml loaded, so it can be overridden
export TEST_ROOT="$(dirname "${BASH_SOURCE[0]}")"
export SCRIPT_DIR="${SCRIPT_DIR:-$(cd "${TEST_ROOT}/lib" && pwd)}"
export SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-${SCRIPT_DIR}/../../lib}"

# =============================================================================
# STEP 2: INITIALIZATION
# -----------------------------------------------------------------------------
# Set up common variables used for hole-punch tests by processing the command
# line arguments and setting up environment variables. Also source all
# libraries needed.
# =============================================================================

# Initialize and export common environment variables (paths, flags, defaults)
source "${SCRIPT_LIB_DIR}/lib-common-init.sh"
init_common_variables
init_cache_dirs

# Hook up ctrl+c handler
trap handle_shutdown INT

# Hole-punch-specific filtering variables
export RELAY_SELECT="${RELAY_SELECT:-}"
export RELAY_IGNORE="${RELAY_IGNORE:-}"
export ROUTER_SELECT="${ROUTER_SELECT:-}"
export ROUTER_IGNORE="${ROUTER_IGNORE:-}"

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-github-snapshots.sh"
source "${SCRIPT_LIB_DIR}/lib-global-services.sh"
source "${SCRIPT_LIB_DIR}/lib-image-building.sh"
source "${SCRIPT_LIB_DIR}/lib-image-naming.sh"
source "${SCRIPT_LIB_DIR}/lib-inputs-yaml.sh"
source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-snapshot-creation.sh"
source "${SCRIPT_LIB_DIR}/lib-snapshot-images.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"
source "${SCRIPT_LIB_DIR}/lib-test-execution.sh"
source "${SCRIPT_LIB_DIR}/lib-test-filtering.sh"
source "${SCRIPT_LIB_DIR}/lib-test-images.sh"

# Print the libp2p banner
print_banner

# Show help
show_help() {
  cat <<EOF
libp2p Hole Punch Interoperability Test Runner

Usage: $0 [options]

Filtering Options:
  Implementation Filtering:
    --impl-select VALUE         Select implementations (pipe-separated patterns)
    --impl-ignore VALUE         Ignore implementations (pipe-separated patterns)

  Relay/Router Filtering:
    --relay-select VALUE        Select relays (pipe-separated patterns)
    --relay-ignore VALUE        Ignore relays (pipe-separated patterns)
    --router-select VALUE       Select routers (pipe-separated patterns)
    --router-ignore VALUE       Ignore routers (pipe-separated patterns)

  Component Filtering:
    --transport-select VALUE    Select transports (pipe-separated patterns)
    --transport-ignore VALUE    Ignore transports (pipe-separated patterns)
    --secure-select VALUE       Select secure channels (pipe-separated patterns)
    --secure-ignore VALUE       Ignore secure channels (pipe-separated patterns)
    --muxer-select VALUE        Select muxers (pipe-separated patterns)
    --muxer-ignore VALUE        Ignore muxers (pipe-separated patterns)

  Test Name Filtering:
    --test-select VALUE         Select tests by name/ID (pipe-separated patterns)
    --test-ignore VALUE         Ignore tests by name/ID (pipe-separated patterns)

Configuration Options:
  --workers VALUE               Number of parallel workers (default: $WORKER_COUNT)
  --cache-dir VALUE             Cache directory (default: /srv/cache)

Execution Options:
  --snapshot                    Create test pass snapshot after completion
  --debug                       Enable debug mode (sets DEBUG=true in test containers)
  --force-matrix-rebuild        Force regeneration of test matrix (bypass cache)
  --force-image-rebuild         Force rebuilding of all docker images (bypass cache)
  --yes, -y                     Skip confirmation prompt and run tests immediately

Information Options:
  --check-deps                  Only check dependencies and exit
  --list-images                 List all image types and exit
  --list-tests                  List all selected tests and exit
  --show-ignored                Show the list of ignored tests
  --help                        Show this help message

Filter Syntax:
  Basic patterns:      "rust-v0.56|go-v0.45"    (match any)
  Alias expansion:     "~rust"                  (expand rust alias)
  Negated alias:       "!~rust"                 (everything NOT matching rust)
  Negated pattern:     "!experimental"          (everything NOT matching experimental)

Filter Processing Order:
  1. SELECT filters narrow from complete list (empty = select all)
  2. IGNORE filters remove from selected set (empty = ignore none)
  3. TEST filters apply to final test names/IDs

Examples:
  # Select only rust implementations
  $0 --impl-select "~rust"

  # Select rust, but not docker images that fail to build
  $0 --impl-select "~rust" --test-ignore "~failing"

  # Test only TCP transport
  $0 --transport-select "tcp"

  # Select specific relay and router
  $0 --relay-select "linux" --router-select "linux"

  # Run specific test by name
  $0 --test-select "rust-v0.56 x go-v0.45"

  # Traditional usage
  $0 --cache-dir /srv/cache --workers 4

Dependencies:
  Required: bash 4.0+, docker 20.10+ (or podman), docker-compose, yq 4.0+
            wget, zip, unzip, tar, gzip, bc, sha256sum, cut, timeout, flock
            Text utilities: awk, sed, grep, sort, head, tail, wc, tr, paste, cat
            File utilities: mkdir, cp, mv, rm, chmod, find, xargs, basename, dirname, mktemp
            System utilities: date, sleep, nproc, uname, hostname, ps
  Optional: gnuplot (box plots), git (submodule-based builds)
  Run with --check-deps to verify installation.

EOF
}

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    # Implementation filtering
    --impl-select) IMPL_SELECT="$2"; shift 2 ;;
    --impl-ignore) IMPL_IGNORE="$2"; shift 2 ;;

    # Relay/Router filtering (hole-punch specific)
    --relay-select) RELAY_SELECT="$2"; shift 2 ;;
    --relay-ignore) RELAY_IGNORE="$2"; shift 2 ;;
    --router-select) ROUTER_SELECT="$2"; shift 2 ;;
    --router-ignore) ROUTER_IGNORE="$2"; shift 2 ;;

    # Component filtering
    --transport-select) TRANSPORT_SELECT="$2"; shift 2 ;;
    --transport-ignore) TRANSPORT_IGNORE="$2"; shift 2 ;;
    --secure-select) SECURE_SELECT="$2"; shift 2 ;;
    --secure-ignore) SECURE_IGNORE="$2"; shift 2 ;;
    --muxer-select) MUXER_SELECT="$2"; shift 2 ;;
    --muxer-ignore) MUXER_IGNORE="$2"; shift 2 ;;

    # Test name filtering
    --test-select) TEST_SELECT="$2"; shift 2 ;;
    --test-ignore) TEST_IGNORE="$2"; shift 2 ;;

    # Configuration options
    --workers) WORKER_COUNT="$2"; shift 2 ;;
    --cache-dir) CACHE_DIR="$2"; shift 2 ;;

    # Execution options
    --snapshot) CREATE_SNAPSHOT=true; shift ;;
    --debug) DEBUG=true; shift ;;
    --force-matrix-rebuild) FORCE_MATRIX_REBUILD=true; shift ;;
    --force-image-rebuild) FORCE_IMAGE_REBUILD=true; shift ;;
    -y|--yes) AUTO_YES=true; shift ;;

    # Information options
    --check-deps) CHECK_DEPS=true; shift ;;
    --list-images) LIST_IMAGES=true; shift ;;
    --list-tests) LIST_TESTS=true; shift ;;
    --show-ignored) SHOW_IGNORED=true; shift ;;
    --help|-h) show_help; exit 0 ;;

    *) echo "Unknown option: ${1}"; echo ""; show_help; exit 1 ;;
  esac
done

# Generate test run key and test pass name
export TEST_TYPE="hole-punch"
export TEST_RUN_KEY=$(compute_test_run_key \
  "${IMAGES_YAML}" \
  "${IMPL_SELECT}" \
  "${IMPL_IGNORE}" \
  "${RELAY_SELECT}" \
  "${RELAY_IGNORE}" \
  "${ROUTER_SELECT}" \
  "${ROUTER_IGNORE}" \
  "${TRANSPORT_SELECT}" \
  "${TRANSPORT_IGNORE}" \
  "${SECURE_SELECT}" \
  "${SECURE_IGNORE}" \
  "${MUXER_SELECT}" \
  "${MUXER_IGNORE}" \
  "${TEST_SELECT}" \
  "${TEST_IGNORE}" \
  "${DEBUG}" \
)
export TEST_PASS_NAME="${TEST_TYPE}-${TEST_RUN_KEY}-$(date +%H%M%S-%d-%m-%Y)"
export TEST_PASS_DIR="${TEST_RUN_DIR}/${TEST_PASS_NAME}"

# =============================================================================
# STEP 3.A: LIST IMAGES AND EXIT
# -----------------------------------------------------------------------------
# This loads the implementations, relays, and routers from the images.yaml file
# and prints them out nicely and exits. This is triggered by the
# `--list-images` command line argument
# =============================================================================

# List images
if [ "${LIST_IMAGES}" == "true" ]; then
  if [ ! -f "${IMAGES_YAML}" ]; then
    print_error "${IMAGES_YAML} not found"
    exit 1
  fi

  print_header "Available Docker Images"
  indent

  # Get and print relays
  readarray -t all_relays_ids < <(get_entity_ids "relays")
  print_list "Relays" all_relays_ids

  echo ""

  # Get and print routers
  readarray -t all_routers_ids < <(get_entity_ids "routers")
  print_list "Routers" all_routers_ids

  echo ""

  # Get and print implementations
  readarray -t all_image_ids < <(get_entity_ids "implementations")
  print_list "Implementations" all_image_ids

  echo ""
  unindent
  exit 0
fi

# =============================================================================
# STEP 3.B: LIST TESTS AND EXIT
# -----------------------------------------------------------------------------
# This creates a temporary folder, runs the test matrix generation, then lists
# the tests that are selected to run and which ones are ignored based on the
# environment and command line arguments. This is triggered by the
# `--list-tests` command line argument
# =============================================================================

# List tests
if [ "${LIST_TESTS}" == "true" ]; then
  # Create temporary directory for test matrix generation
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf \"${TEMP_DIR}\"" EXIT

  export TEST_PASS_DIR="${TEMP_DIR}"
  export TEST_PASS_NAME="temp-list"
  export CACHE_DIR
  export DEBUG
  export TEST_IGNORE RELAY_IGNORE ROUTER_IGNORE TRANSPORT_IGNORE SECURE_IGNORE MUXER_IGNORE
  export FORCE_MATRIX_REBUILD

  print_header "Generating test matrix..."
  indent

  # Generate test matrix (don't suppress output to show Test Matrix Generation section)
  bash "${SCRIPT_DIR}/generate-tests.sh" || true

  # Check if matrix was created successfully
  if [ ! -f "${TEMP_DIR}/test-matrix.yaml" ]; then
    print_error "Failed to generate test matrix"
    bash "${SCRIPT_DIR}/generate-tests.sh" 2>&1 | tail -10  # Show error output
    unindent
    exit 1
  fi
  unindent
  echo ""

  print_header "Test Selection..."
  indent

  # Get and print the selected main tests
  readarray -t selected_tests < <(get_entity_ids "tests" "${TEMP_DIR}/test-matrix.yaml")
  print_list "Selected tests" selected_tests

  echo ""

  # Get and maybe print the ignored main tests
  readarray -t ignored_tests < <(get_entity_ids "ignoredTests" "${TEMP_DIR}/test-matrix.yaml")
  if [ "${SHOW_IGNORED}" == "true" ]; then
    print_list "Ignored tests" ignored_tests
    echo ""
  fi

  print_message "Total selected: ${#selected_tests[@]} tests"
  print_message "Total ignored: ${#ignored_tests[@]} tests"
  echo ""

  unindent
  exit 0
fi

# =============================================================================
# STEP 3.C: CHECK DEPS AND EXIT
# -----------------------------------------------------------------------------
# This runs the dependency checking and returns its results. This is triggered
# by the `--list-deps` command line argument
# =============================================================================

# Check dependencies
if [ "${CHECK_DEPS}" == "true" ]; then
  print_header "Checking dependencies..."
  indent
  bash "${SCRIPT_LIB_DIR}/check-dependencies.sh" docker yq || {
    echo ""
    print_error "Error: Missing required dependencies."
    print_message "Run '${0}' --check-deps to see details."
    unindent
    exit 1
  }
  unindent
  exit 0
fi

# =============================================================================
# STEP 4: INITIALIZE
# -----------------------------------------------------------------------------
# Create the folders needed for storing the test run artifacts. Also output all
# of the settings, check for dependencies, and which docker compose command is
# to be used.
# =============================================================================

print_header "Hole-punch Test"
indent

print_message "Test Type: ${TEST_TYPE}"
print_message "Test Run Key: ${TEST_RUN_KEY}"
print_message "Test Pass: ${TEST_PASS_NAME}"
print_message "Test Pass Dir: ${TEST_PASS_DIR}"
print_message "Cache Dir: ${CACHE_DIR}"
print_message "Workers: ${WORKER_COUNT}"
# Display filters (only if set)
[ -n "${IMPL_SELECT}" ] && print_message "Impl Select: ${IMPL_SELECT}"
[ -n "${IMPL_IGNORE}" ] && print_message "Impl Ignore: ${IMPL_IGNORE}"
[ -n "${RELAY_SELECT}" ] && print_message "Relay Select: ${RELAY_SELECT}"
[ -n "${RELAY_IGNORE}" ] && print_message "Relay Ignore: ${RELAY_IGNORE}"
[ -n "${ROUTER_SELECT}" ] && print_message "Router Select: ${ROUTER_SELECT}"
[ -n "${ROUTER_IGNORE}" ] && print_message "Router Ignore: ${ROUTER_IGNORE}"
[ -n "${TRANSPORT_SELECT}" ] && print_message "Transport Select: ${TRANSPORT_SELECT}"
[ -n "${TRANSPORT_IGNORE}" ] && print_message "Transport Ignore: ${TRANSPORT_IGNORE}"
[ -n "${SECURE_SELECT}" ] && print_message "Secure Select: ${SECURE_SELECT}"
[ -n "${SECURE_IGNORE}" ] && print_message "Secure Ignore: ${SECURE_IGNORE}"
[ -n "${MUXER_SELECT}" ] && print_message "Muxer Select: ${MUXER_SELECT}"
[ -n "${MUXER_IGNORE}" ] && print_message "Muxer Ignore: ${MUXER_IGNORE}"
[ -n "${TEST_SELECT}" ] && print_message "Test Select: ${TEST_SELECT}"
[ -n "${TEST_IGNORE}" ] && print_message "Test Ignore: ${TEST_IGNORE}"
print_message "Create Snapshot: ${CREATE_SNAPSHOT}"
print_message "Debug: ${DEBUG}"
print_message "Force Matrix Rebuild: ${FORCE_MATRIX_REBUILD}"
print_message "Force Image Rebuild: ${FORCE_IMAGE_REBUILD}"
echo ""

# Set up the folder structure for the output
mkdir -p "${TEST_PASS_DIR}"/{logs,results,docker-compose}

# Generate inputs.yaml to capture the current environment and command line arguments
generate_inputs_yaml "${TEST_PASS_DIR}/inputs.yaml" "$TEST_TYPE" "${ORIGINAL_ARGS[@]}"

echo ""
unindent

# Check dependencies for normal execution
print_header "Checking dependencies..."
indent
bash "${SCRIPT_LIB_DIR}/check-dependencies.sh" docker yq || {
  echo ""
  print_error "Error: Missing required dependencies."
  print_message "Run '${0}' --check-deps to see details."
  unindent
  exit 1
}

# Read and export the docker compose command detected by check-dependencies.sh
if [ -f /tmp/docker-compose-cmd.txt ]; then
  export DOCKER_COMPOSE_CMD=$(cat /tmp/docker-compose-cmd.txt)
else
  print_error "Error: Could not determine docker compose command"
  unindent
  exit 1
fi
unindent
echo ""

# Start timing (moved before server setup)
TEST_START_TIME=$(date +%s)

# =============================================================================
# STEP 5: GENERATE TEST MATRIX
# -----------------------------------------------------------------------------
# This either loads an already generated test matrix from the cache or it
# generates a new one and caches it. This applies the filtering and the test
# matrix file contains the selected and ignored tests
# =============================================================================

# Generate test matrix
print_header "Generating test matrix..."
indent

bash "${SCRIPT_DIR}/generate-tests.sh" || {
  print_error "Test matrix generation failed"
  unindent
  exit 1
}
unindent
echo ""

# =============================================================================
# STEP 6: PRINT TEST SELECTION
# -----------------------------------------------------------------------------
# This loads the test matrix data and prints it out. If AUTO_YES is not true,
# then prompt the user if they would like to continue.
# =============================================================================

# Display test selection and get confirmation
print_header "Test Selection..."
indent

# Get and print the selected main tests
readarray -t selected_main_tests < <(get_entity_ids "tests" "${TEST_PASS_DIR}/test-matrix.yaml")
print_list "Selected main tests" selected_main_tests

echo ""

# Get and maybe print the ignored main tests
readarray -t ignored_main_tests < <(get_entity_ids "ignoredTests" "${TEST_PASS_DIR}/test-matrix.yaml")
if [ "${SHOW_IGNORED}" == "true" ]; then
  print_list "Ignored main tests" ignored_main_tests
  echo ""
fi

TEST_COUNT=${#selected_main_tests[@]}
TOTAL_TESTS=${TEST_COUNT}

print_message "Total selected: ${TOTAL_TESTS} tests"
print_message "Total ignored: ${#ignored_main_tests[@]} tests"
echo ""
unindent

# Get unique implementations from main tests
REQUIRED_IMAGES=$(mktemp)
yq eval '.tests[].dialer.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
yq eval '.tests[].listener.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
yq eval '.tests[].dialerRouter.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
yq eval '.tests[].listenerRouter.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
yq eval '.tests[].relay.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
sort -u "${REQUIRED_IMAGES}" -o "${REQUIRED_IMAGES}"
IMAGE_COUNT=$(wc -l < "${REQUIRED_IMAGES}")

# Prompt for confirmation unless auto-approved
indent
if [ "${AUTO_YES}" != true ]; then
  read -p "  Build ${IMAGE_COUNT} Docker images and execute ${TOTAL_TESTS} tests? (Y/n): " response
  response=${response:-Y}

  if [[ ! "${response}" =~ ^[Yy]$ ]]; then
    echo ""
    print_error "Test execution cancelled."
    unindent
    exit 0
  fi
else
  print_success "Automatically running the tests..."
fi
unindent

# =============================================================================
# STEP 7: BUILD MISSING DOCKER IMAGES
# -----------------------------------------------------------------------------
# This attempts to build the missing docker images needed to run the selected
# tests.
# =============================================================================

# Build Docker images
echo ""
print_header "Building Docker images..."
indent

print_message "Building ${IMAGE_COUNT} required implementations"

# Build each required implementation using pipe-separated list
IMAGE_IDS=$(cat "${REQUIRED_IMAGES}" | paste -sd'|' -)

# Build images from implementations
build_images_from_section "routers" "${IMAGE_IDS}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "relays" "${IMAGE_IDS}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "implementations" "${IMAGE_IDS}" "${FORCE_IMAGE_REBUILD}"

print_success "All images built successfully"

rm -f "${REQUIRED_IMAGES}"
unindent
echo ""

# =============================================================================
# STEP 8: RUN TESTS
# -----------------------------------------------------------------------------
# This starts global services (e.g. Redis), then runs the baseline tests
# followed by the main tests and then stops the global services.
# =============================================================================

# Start global services
print_header "Staring global services..."
indent
start_redis_service "${TEST_TYPE}-network" "${TEST_TYPE}-redis" || {
  print_error "Starting global services failed"
  unindent
  return 1
}
unindent
echo ""

# Run main transport interop tests
print_header "Running tests... (${WORKER_COUNT} workers)"
indent

# Initialize results file
TEST_RESULTS_FILE="${TEST_PASS_DIR}/results.yaml.tmp"
> "${TEST_RESULTS_FILE}"

# Run tests with parallel workers
run_test() {
  local index="${1}"
  local name=$(yq eval ".tests[${index}].id" "${TEST_PASS_DIR}/test-matrix.yaml")

  source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"

  # Run test using run-single-test.sh (now reads from test-matrix.yaml)
  # Results are written to results.yaml.tmp by the script
  # This executes in parallel without the lock
  if bash "${SCRIPT_DIR}/run-single-test.sh" "${index}" "tests" "${TEST_PASS_DIR}/results.yaml.tmp"; then
    result="[SUCCESS]"
    exit_code=0
  else
    result="[FAILED]"
    exit_code=1
  fi

  # Serialize the message printing using flock (prevents interleaved output)
  (
    flock -x 200
    print_message "[$((index + 1))/${TEST_COUNT}] ${name}...${result}"
  ) 200>/tmp/transport-test-output.lock

  return ${exit_code}
}

export TEST_COUNT
export -f run_test

# Run tests in parallel using xargs
# Note: Some tests may fail, but we want to continue to collect results
# So we use || true to ensure xargs exit code doesn't stop the script
seq 0 $((TEST_COUNT - 1)) | xargs -P "${WORKER_COUNT}" -I {} bash -c 'run_test {}' || true

unindent
echo ""

# Stop global services
print_header "Stopping global services..."
indent
stop_redis_service "${TEST_TYPE}-network" "${TEST_TYPE}-redis" || {
  print_error "Stopping global services failed"
  unindent
  return 1
}
unindent
echo ""

TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

# =============================================================================
# STEP 9: COLLECT RESULTS
# -----------------------------------------------------------------------------
# This appends all of the results files to the single results.yaml in the
# output directory and then displays a summary
# =============================================================================

# Collect results
print_header "Collecting results..."
indent

# Count pass/fail from individual result files
PASSED=0
FAILED=0
if [ -f "${TEST_PASS_DIR}/results.yaml.tmp" ]; then
  PASSED=$(grep -c "status: pass" "${TEST_PASS_DIR}/results.yaml.tmp" || true)
  FAILED=$(grep -c "status: fail" "${TEST_PASS_DIR}/results.yaml.tmp" || true)
fi

# Handle empty results
PASSED=${PASSED:-0}
FAILED=${FAILED:-0}

# Generate final results.yaml
cat > "${TEST_PASS_DIR}/results.yaml" <<EOF
metadata:
  testPass: ${TEST_PASS_NAME}
  startedAt: $(date -d @"${TEST_START_TIME}" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -r "${TEST_START_TIME}" -u +%Y-%m-%dT%H:%M:%SZ)
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration: ${TEST_DURATION}s
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: ${WORKER_COUNT}

summary:
  total: ${TEST_COUNT}
  passed: ${PASSED}
  failed: ${FAILED}

tests:
EOF

# Append test results if they exist
if [ -f "${TEST_PASS_DIR}/results.yaml.tmp" ]; then
    cat "${TEST_PASS_DIR}/results.yaml.tmp" >> "${TEST_PASS_DIR}/results.yaml"
    rm "${TEST_PASS_DIR}/results.yaml.tmp"
fi

print_message "Results:"
indent
print_message "Total: ${TEST_COUNT}"
print_success "Passed: ${PASSED}"
print_error "Failed: ${FAILED}"

# List failed tests if any
if [ "${FAILED}" -gt 0 ]; then
  readarray -t FAILED_TESTS < <(yq eval '.tests[]? | select(.status == "fail") | .name' "${TEST_PASS_DIR}/results.yaml" 2>/dev/null || true)
  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    for test_name in "${FAILED_TESTS[@]}"; do
      echo "    - ${test_name}"
    done
  fi
fi


unindent
echo ""

# Display execution time
HOURS=$((TEST_DURATION / 3600))
MINUTES=$(((TEST_DURATION % 3600) / 60))
SECONDS=$((TEST_DURATION % 60))
print_message "$(printf "Total time: %02d:%02d:%02d\n" "${HOURS}" "${MINUTES}" "${SECONDS}")"
echo ""

# Display status message
if [ "${FAILED}" -eq 0 ]; then
  print_success "All tests passed!"
  EXIT_FINAL=0
else
  print_error "${FAILED} test(s) failed"
  EXIT_FINAL=1
fi

unindent
echo ""

# =============================================================================
# STEP 10: GENERATE RESULTS DASHBOARD
# -----------------------------------------------------------------------------
# This creates the Markdown version for injecting into the README.md file for
# this test. If `pandoc` is installed, an HTML version is gnerated.
# =============================================================================

# Generate results dashboard
print_header "Generating results dashboard..."
indent

print_success "Generated ${TEST_PASS_DIR}/results.yaml"
bash "${SCRIPT_DIR}/generate-dashboard.sh" || {
  print_error "Dashboard generation failed"
}
echo ""
print_success "Dashboard generation complete"
unindent
echo ""

# =============================================================================
# STEP 11: CREATE SNAPSHOT
# -----------------------------------------------------------------------------
# This copies all necessary scripts and input files to the output directory so
# that it becomes a standalone version of this test that can be emitted as an
# artifact when run as a CI/CD step. It then contains everything needed to
# subsequently re-run the test exactly as it was run for debugging and
# analysis.
# =============================================================================

# Create snapshot (if requested)
if [ "${CREATE_SNAPSHOT}" == "true" ]; then
  print_header "Creating test pass snapshot..."
  indent
  create_snapshot || {
    print_error "Snapshot creation failed"
  }
  unindent
fi

exit "${EXIT_FINAL}"

