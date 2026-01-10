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

# Hole-punch-specific variables
RELAY_IGNORE="${RELAY_IGNORE:-}"
ROUTER_IGNORE="${ROUTER_IGNORE:-}"

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

Options:
  --test-ignore VALUE        Ignore tests (pipe-separated substrings)
  --relay-ignore VALUE       Ignore relays (pipe-separated substrings)
  --router-ignore VALUE      Ignore routers (pipe-separated substrings)
  --transport-ignore VALUE   Ignore given transport (pipe-separated)
  --secure-ignore VALUE      Ignore given secure channel (pipe-separated)
  --muxer-ignore VALUE       Ignore given muxer (pipe-separated)
  --workers VALUE            Number of parallel workers (default: $WORKER_COUNT)
  --cache-dir VALUE          Cache directory (default: /srv/cache)
  --snapshot                 Create test pass snapshot after completion
  --debug                    Enable debug mode (sets DEBUG=true in test containers)
  --force-matrix-rebuild     Force regeneration of test matrix (bypass cache)
  --force-image-rebuild      Force rebuilding of all docker images (bypass cache)
  --yes, -y                  Skip confirmation prompt and run tests immediately
  --check-deps               Only check dependencies and exit
  --list-images              List all image types used by this test suite and exit
  --list-tests               List all selected tests and exit
  --show-ignored             Shows the list of ignored tests
  --help                     Show this help message

Examples:
  $0 --cache-dir /srv/cache --workers 4
  $0 --test-ignore "tcp"
  $0 --relay-ignore "!linux" --router-ignore "!linux" --force-matrix-rebuild
  $0 --list-images
  $0 --list-tests --test-ignore "!~rust"
  $0 --snapshot --force-image-rebuild

Dependencies:
  bash 4.0+, docker 20.10+, yq 4.0+, wget, zip, unzip
  Run with --check-deps to verify installation.

EOF
}

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --test-ignore) TEST_IGNORE="$2"; shift 2 ;;
    --relay-ignore) RELAY_IGNORE="$2"; shift 2 ;;
    --router-ignore) ROUTER_IGNORE="$2"; shift 2 ;;
    --transport-ignore) TRANSPORT_IGNORE="$2"; shift 2;;
    --secure-ignore) SECURE_IGNORE="$2"; shift 2;;
    --muxer-ignore) MUXER_IGNORE="$2"; shift 2;;
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
    --show-ignored) SHOW_IGNORED=true; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Unknown option: ${1}"; echo ""; show_help; exit 1 ;;
  esac
done

# Generate test run key and test pass name
export TEST_TYPE="hole-punch"
export TEST_RUN_KEY=$(compute_test_run_key \
  "${IMAGES_YAML}" \
  "${TEST_IGNORE}" \
  "${RELAY_IGNORE}" \
  "${ROUTER_IGNORE}" \
  "${TRANSPORT_IGNORE}" \
  "${SECURE_IGNORE}" \
  "${MUXER_IGNORE}" \
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

print_header "Performance Test"
indent

print_message "Test Type: ${TEST_TYPE}"
print_message "Test Run Key: ${TEST_RUN_KEY}"
print_message "Test Pass: ${TEST_PASS_NAME}"
print_message "Test Pass Dir: ${TEST_PASS_DIR}"
print_message "Cache Dir: ${CACHE_DIR}"
print_message "Workers: ${WORKER_COUNT}"
[ -n "${TEST_IGNORE}" ] && print_message "Test Ignore: ${TEST_IGNORE}"
[ -n "${RELAY_IGNORE}" ] && print_message "Relay Ignore: ${RELAY_IGNORE}"
[ -n "${ROUTER_IGNORE}" ] && print_message "Router Ignore: ${ROUTER_IGNORE}"
[ -n "${TRANSPORT_IGNORE}" ] && print_message "Transport Ignore: ${TRANSPORT_IGNORE}"
[ -n "${SECURE_IGNORE}" ] && print_message "Secure Ignore: ${SECURE_IGNORE}"
[ -n "${MUXER_IGNORE}" ] && print_message "Muxer Ignore: ${MUXER_IGNORE}"
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





export CACHE_DIR
export DEBUG
export TEST_SELECT
export TEST_IGNORE
export RELAY_SELECT
export RELAY_IGNORE
export ROUTER_SELECT
export ROUTER_IGNORE
export FORCE_MATRIX_REBUILD
export TEST_PASS_DIR

print_header "Hole Punch Interoperability Test Suite"

# Source test key generation functions
source "${SCRIPT_LIB_DIR}/lib-test-keys.sh"

# Generate test run key and test pass name
TEST_TYPE="hole-punch"
TEST_RUN_KEY=$(compute_test_run_key "images.yaml" "${TEST_SELECT}||${TEST_IGNORE}||${RELAY_SELECT}||${RELAY_IGNORE}||${ROUTER_SELECT}||${ROUTER_IGNORE}||${DEBUG}")
TEST_PASS_NAME="${TEST_TYPE}-${TEST_RUN_KEY}-$(date +%H%M%S-%d-%m-%Y)"
export TEST_PASS_DIR="${TEST_RUN_DIR}/${TEST_PASS_NAME}"
export TEST_RUN_KEY

print_message "Test Pass: ${TEST_PASS_NAME}"
print_message "Cache Dir: ${CACHE_DIR}"
print_message "Test Pass Dir: ${TEST_PASS_DIR}"
print_message "Workers: ${WORKER_COUNT}"
[ -n "${TEST_SELECT}" ] && print_message "Test Select: ${TEST_SELECT}"
[ -n "${TEST_IGNORE}" ] && print_message "Test Ignore: ${TEST_IGNORE}"
[ -n "${RELAY_SELECT}" ] && print_message "Relay Select: ${RELAY_SELECT}"
[ -n "${RELAY_IGNORE}" ] && print_message "Relay Ignore: ${RELAY_IGNORE}"
[ -n "${ROUTER_SELECT}" ] && print_message "Router Select: ${ROUTER_SELECT}"
[ -n "${ROUTER_IGNORE}" ] && print_message "Router Ignore: ${ROUTER_IGNORE}"
print_message "Create Snapshot: ${CREATE_SNAPSHOT}"
print_message "Debug: ${DEBUG}"
print_message "Force Matrix Rebuild: ${FORCE_MATRIX_REBUILD}"
print_message "Force Image Rebuild: ${FORCE_IMAGE_REBUILD}"
echo ""

START_TIME=$(date +%s)

# Create test pass directory and copy configuration
mkdir -p "${TEST_PASS_DIR}"
mkdir -p "${TEST_PASS_DIR}"/{logs,results,docker-compose}

cp images.yaml "${TEST_PASS_DIR}/"

# Generate inputs.yaml for reproducibility
source "${SCRIPT_LIB_DIR}/lib-inputs-yaml.sh"
generate_inputs_yaml "${TEST_PASS_DIR}/inputs.yaml" "${TEST_TYPE}" "${ORIGINAL_ARGS[@]}"

export TEST_PASS_NAME

# 1. Check dependencies
print_header "Checking dependencies..."
if ! bash "${SCRIPT_LIB_DIR}/check-dependencies.sh"; then
  print_error "Dependency check failed. Please install missing dependencies."
  exit 1
fi

# Read and export the docker compose command detected by check-dependencies.sh
if [ -f /tmp/docker-compose-cmd.txt ]; then
  export DOCKER_COMPOSE_CMD=$(cat /tmp/docker-compose-cmd.txt)
  print_message "Using: ${DOCKER_COMPOSE_CMD}"
else
  print_error "Could not determine docker compose command"
  exit 1
fi





# 2. Generate test matrix FIRST (before building images)
print_header "╲ Generating test matrix..."
bash lib/generate-tests.sh

# 3. Display test selection and get confirmation
TEST_COUNT=$(yq eval '.metadata.totalTests' "${TEST_PASS_DIR}/test-matrix.yaml")

if [ "${TEST_COUNT}" -eq 0 ]; then
  print_message "No tests in matrix, skipping image builds"
else
  # Extract unique RELAYS from test matrix
  # Note: Relays do NOT have dialOnly - all relays in matrix should be built
  REQUIRED_RELAYS=$(mktemp)
  yq eval '.tests[].relay' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u > "${REQUIRED_RELAYS}"
  RELAY_FILTER=$(cat "${REQUIRED_RELAYS}" | paste -sd'|' -)
  rm -f "${REQUIRED_RELAYS}"

    # Extract unique ROUTERS from test matrix (dialer router + listener router)
    # Note: Routers do NOT have dialOnly - all routers in matrix should be built
    REQUIRED_ROUTERS=$(mktemp)
    yq eval '.tests[].dialerRouter' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u > "${REQUIRED_ROUTERS}"
    yq eval '.tests[].listenerRouter' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u >> "${REQUIRED_ROUTERS}"
    sort -u "${REQUIRED_ROUTERS}" -o "${REQUIRED_ROUTERS}"
    ROUTER_FILTER=$(cat "${REQUIRED_ROUTERS}" | paste -sd'|' -)
    rm -f "${REQUIRED_ROUTERS}"

    # Extract unique IMPLEMENTATIONS from test matrix (dialer + listener)
    # Note: Implementations CAN have dialOnly - already filtered during test generation
    REQUIRED_IMAGES=$(mktemp)
    yq eval '.tests[].dialer' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u > "${REQUIRED_IMAGES}"
    yq eval '.tests[].listener' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u >> "${REQUIRED_IMAGES}"
    sort -u "${REQUIRED_IMAGES}" -o "${REQUIRED_IMAGES}"

    # Also add base images for any browser-type implementations
    REQUIRED_IMPLS_WITH_DEPS=$(mktemp)
    cp "${REQUIRED_IMAGES}" "${REQUIRED_IMPLS_WITH_DEPS}"

    while IFS= read -r image_id; do
      # Check if this is a browser-type implementation
      source_type=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .source.type" images.yaml)
      if [ "${source_type}" == "browser" ]; then
        # Add its base image as a dependency
        base_image=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .source.baseImage" images.yaml)
        echo "${base_image}" >> "${REQUIRED_IMPLS_WITH_DEPS}"
      fi
    done < "${REQUIRED_IMAGES}"

    # Sort and deduplicate
    sort -u "${REQUIRED_IMPLS_WITH_DEPS}" -o "${REQUIRED_IMPLS_WITH_DEPS}"
    IMAGE_FILTER=$(cat "${REQUIRED_IMPLS_WITH_DEPS}" | paste -sd'|' -)

    # Count what we're building
    RELAY_COUNT=$(echo "${RELAY_FILTER}" | tr '|' '\n' | grep -v '^$' | wc -l)
    ROUTER_COUNT=$(echo "${ROUTER_FILTER}" | tr '|' '\n' | grep -v '^$' | wc -l)
    IMAGE_COUNT=$(wc -l < "${REQUIRED_IMPLS_WITH_DEPS}")

    print_message "Building ${RELAY_COUNT} relay(s), ${ROUTER_COUNT} router(s), ${IMAGE_COUNT} implementation(s) (including base images)"
    echo ""

    # Build images with filters (relay, router, impl filters passed separately)
    print_message "bash lib/build-images.sh \"${RELAY_FILTER}\" \"${ROUTER_FILTER}\" \"${IMAGE_FILTER}\" \"${FORCE_IMAGE_REBUILD}\""
    bash lib/build-images.sh "${RELAY_FILTER}" "${ROUTER_FILTER}" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"

    rm -f "${REQUIRED_IMAGES}" "${REQUIRED_IMPLS_WITH_DEPS}"
fi

# Display test list and prompt for confirmation
echo ""

print_header "Test selection..."
print_message "Selected tests:"

# Read test matrix
TEST_COUNT=$(yq eval '.metadata.totalTests' "${TEST_PASS_DIR}/test-matrix.yaml")
ignored_count=$(yq eval '.metadata.ignoredTests' "${TEST_PASS_DIR}/test-matrix.yaml")

# Display active tests (extract all names in one yq call)
if [ "${TEST_COUNT}" -gt 0 ]; then
  yq eval '.tests[].name' "${TEST_PASS_DIR}/test-matrix.yaml" | while read -r test_name; do
  print_success "${test_name}"
done
fi

# Display ignored tests (extract all names in one yq call)
if [ "${ignored_count}" -gt 0 ]; then
  echo ""
  print_message "Ignored tests:"
  yq eval '.ignoredTests[].name' "${TEST_PASS_DIR}/test-matrix.yaml" | while read -r test_name; do
  print_error "${test_name} [ignored]"
done
fi

echo ""

print_message "Total: ${TEST_COUNT} tests to execute, ${ignored_count} ignored"

# Prompt user for confirmation (unless -y flag was set)
if [ "${AUTO_YES}" == "false" ]; then
  read -p "Execute ${TEST_COUNT} tests? (Y/n): " response
  response=${response:-Y}  # Default to Y if user just presses enter

  if [[ ! "${response}" =~ ^[Yy]$ ]]; then
    print_error "Test execution cancelled."
    exit 0
  fi
fi

# Start global services
print_message "Starting global services..."
bash lib/start-global-services.sh

# Run tests in parallel
print_header "Running tests... (${WORKER_COUNT} workers)"

# Read test matrix and export TEST_COUNT for use in subshells
TEST_COUNT=$(yq eval '.metadata.totalTests' "${TEST_PASS_DIR}/test-matrix.yaml")
export TEST_COUNT

# Initialize results
> "${TEST_PASS_DIR}/results.yaml.tmp"

# Run tests with parallel workers
run_test() {
  local index=${1}
  local name=$(yq eval ".tests[${index}].name" "${TEST_PASS_DIR}/test-matrix.yaml")
  local dialer=$(yq eval ".tests[${index}].dialer" "${TEST_PASS_DIR}/test-matrix.yaml")
  local listener=$(yq eval ".tests[${index}].listener" "${TEST_PASS_DIR}/test-matrix.yaml")
  local transport=$(yq eval ".tests[${index}].transport" "${TEST_PASS_DIR}/test-matrix.yaml")
  local secure=$(yq eval ".tests[${index}].secureChannel" "${TEST_PASS_DIR}/test-matrix.yaml")
  local muxer=$(yq eval ".tests[${index}].muxer" "${TEST_PASS_DIR}/test-matrix.yaml")
  local dialer_router=$(yq eval ".tests[${index}].dialerRouter" "${TEST_PASS_DIR}/test-matrix.yaml")
  local relay=$(yq eval ".tests[${index}].relay" "${TEST_PASS_DIR}/test-matrix.yaml")
  local listener_router=$(yq eval ".tests[${index}].listenerRouter" "${TEST_PASS_DIR}/test-matrix.yaml")

  print_message "[$((index + 1))/${TEST_COUNT}] ${name}"

  start=$(date +%s)
  if bash lib/run-single-test.sh "${name}" "${dialer}" "${listener}" "${transport}" "${secure}" "${muxer}"; then
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
if [ "${status}" == "pass" ]; then
  test_slug=$(echo "${name}" | sed 's/[^a-zA-Z0-9-]/_/g')
  log_file="${TEST_PASS_DIR}/logs/${test_slug}.log"
  if [ -f "${log_file}" ]; then
    # Extract JSON metrics from log
    metrics=$(grep -o '{"handshakePlusOneRTTMillis":[0-9.]*,"pingRTTMilllis":[0-9.]*}' "${log_file}" 2>/dev/null | tail -1)
    if [ -n "${metrics}" ]; then
      handshake_ms=$(echo "${metrics}" | grep -o '"handshakePlusOneRTTMillis":[0-9.]*' | cut -d: -f2)
      ping_ms=$(echo "${metrics}" | grep -o '"pingRTTMilllis":[0-9.]*' | cut -d: -f2)
    fi
  fi
fi

# Append to results (with locking to avoid race conditions)
(
  flock -x 200
  cat >> "${TEST_PASS_DIR}/results.yaml.tmp" <<EOF
  - name: "${name}"
    status: ${status}
    exitCode: ${exit_code}
    duration: ${duration}s
    dialer: ${dialer}
    listener: ${listener}
    transport: ${transport}
EOF
) 200>/tmp/results.lock

return ${exit_code}
}

export -f run_test

# Run tests in parallel using xargs
# Note: Don't exit on failure - we want to collect results even if tests fail
seq 0 $((TEST_COUNT - 1)) | xargs -P "${WORKER_COUNT}" -I {} bash -c 'run_test {}' || true

# Cleanup
print_header "Stopping global services..."
bash lib/stop-global-services.sh

# 6. Collect results
print_header "Collecting results..."

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Count pass/fail
# grep -c outputs "0" and exits with status 1 when count is 0
# Using || true to avoid the || echo 0 adding an extra 0
PASSED=$(grep -c "status: pass" "${TEST_PASS_DIR}/results.yaml.tmp" || true)
FAILED=$(grep -c "status: fail" "${TEST_PASS_DIR}/results.yaml.tmp" || true)

# Handle empty results (when grep finds nothing, it outputs nothing with || true)
PASSED=${PASSED:-0}
FAILED=${FAILED:-0}

# Generate final results.yaml
cat > "${TEST_PASS_DIR}/results.yaml" <<EOF
metadata:
  testPass: ${TEST_PASS_NAME}
  startedAt: $(date -d @${START_TIME} -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -r ${START_TIME} -u +%Y-%m-%dT%H:%M:%SZ)
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration: ${DURATION}s
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: ${WORKER_COUNT}

summary:
  total: ${TEST_COUNT}
  passed: ${PASSED}
  failed: ${FAILED}

tests:
EOF

cat "${TEST_PASS_DIR}/results.yaml.tmp" >> "${TEST_PASS_DIR}/results.yaml"
rm "${TEST_PASS_DIR}/results.yaml.tmp"

# Collect failed test names
FAILED_TESTS=()
if [ "${FAILED}" -gt 0 ]; then
  readarray -t FAILED_TESTS < <(yq eval '.tests[] | select(.status == "fail") | .name' "${TEST_PASS_DIR}/results.yaml")
fi

print_message "Results:"
indent
print_message "Total: ${TEST_COUNT}"
print_success "Passed: ${PASSED}"
print_error "Failed: ${FAILED}"
print_list "Failed Tests:" "${FAILED_TESTS[@]}"
unindent
echo ""


# Display execution time
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))
execution_time=$(printf "Total time: %02d:%02d:%02d\n" ${HOURS} ${MINUTES} ${SECONDS})
print_message "${execution_time}"

# 6. Generate dashboard
print_header "Generating results dashboard..."
bash lib/generate-dashboard.sh

# Final status message
echo ""
if [ "${FAILED}" -eq 0 ]; then
  print_header "✓ All tests passed!"
  EXIT_FINAL=0
else
  print_header "✗ ${FAILED} test(s) failed"
  EXIT_FINAL=1
fi

# 7. Create snapshot (optional)
if [ "${CREATE_SNAPSHOT}" == "true" ]; then
  print_header "Creating test pass snapshot..."
  bash lib/create-snapshot.sh
fi

exit ${EXIT_FINAL}
