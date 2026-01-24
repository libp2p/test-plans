#!/usr/bin/env bash

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
CMD_LINE_ARGS=(${YAML_ARGS[@]+"${YAML_ARGS[@]}"} "$@")

# Set positional parameters to merged args
set -- "${CMD_LINE_ARGS[@]}"

# NOTE: this test can be run and later re-run. When run initially, the
# SCRIPT_DIR is something like `<repo root>/perf/lib` and the SCRIPT_LIB_DIR is
# then `${SCRIPT_DIR}/../../lib`. The SCRIPT_DIR points to where the
# perf-specific test scripts are located and the SCRIPT_LIB_DIR is where the
# scripts that are common to all tests are located. An inputs.yaml file is
# generated to capture these values for re-running the same test later. When
# re-running a test from a snapshot, all scripts are located in the same
# folder: `<snapshot root>/lib` so the inputs.yaml file is used to initialize
# the environment variables so that all scripts load properly.

# Set SCRIPT_LIB_DIR after inputs.yaml loaded, so it can be overridden
export TEST_ROOT="$(dirname "${BASH_SOURCE[0]}")"
export SCRIPT_DIR="${SCRIPT_DIR:-$(cd "${TEST_ROOT}/lib" && pwd)}"
export SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-${SCRIPT_DIR}/../../lib}"

# =============================================================================
# STEP 2: INITIALIZATION
# -----------------------------------------------------------------------------
# Set up common variables used for perf tests by processing the command line
# arguments and setting up environment variables. Also source all libraries
# needed.
# =============================================================================

# Initialize and export common environment variables (paths, flags, defaults)
source "${SCRIPT_LIB_DIR}/lib-common-init.sh"
init_common_variables
init_cache_dirs

# Hook up ctrl+c handler
trap handle_shutdown INT

# Override for perf: Must run 1 test at a time (sequential) to get accurate
# performance results
WORKER_COUNT=1

# Perf-specific filtering variables
export BASELINE_SELECT="${BASELINE_SELECT:-}"
export BASELINE_IGNORE="${BASELINE_IGNORE:-}"

# Perf-specific test parameters
export UPLOAD_BYTES=1073741824     # 1GB default
export DOWNLOAD_BYTES=1073741824   # 1GB default
export ITERATIONS=10
export DURATION_PER_ITERATION=20   # seconds per iteration for throughput tests
export LATENCY_ITERATIONS=100      # iterations for latency test

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
libp2p Performance Test Runner

Usage: ${0} [options]

Filtering Options:
  Implementation Filtering:
    --impl-select VALUE         Select implementations (pipe-separated patterns)
    --impl-ignore VALUE         Ignore implementations (pipe-separated patterns)

  Baseline Filtering:
    --baseline-select VALUE     Select baseline tests (pipe-separated patterns)
    --baseline-ignore VALUE     Ignore baseline tests (pipe-separated patterns)

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
  --upload-bytes VALUE          Bytes to upload per test (default: 1GB)
  --download-bytes VALUE        Bytes to download per test (default: 1GB)
  --iterations VALUE            Number of iterations per test (default: 10)
  --duration VALUE              Duration per iteration for throughput (default: 20s)
  --latency-iterations VALUE    Iterations for latency test (default: 100)
  --cache-dir VALUE             Cache directory (default: /srv/cache)

Execution Options:
  --snapshot                    Create test pass snapshot after completion
  --debug                       Enable debug mode
  --force-matrix-rebuild        Force test matrix regeneration (bypass cache)
  --force-image-rebuild         Force Docker image rebuilds (bypass cache)
  --yes, -y                     Skip confirmation prompts

Information Options:
  --check-deps                  Only check dependencies and exit
  --list-images                 List all image types and exit
  --list-tests                  List all selected tests and exit
  --show-ignored                Show the list of ignored tests
  --help, -h                    Show this help message

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
  ${0} --impl-select "~rust"

  # Select rust, but not docker images that fail to build
  ${0} --impl-select "~rust" --test-ignore "~failing"

  # Test only TCP transport with TLS
  ${0} --transport-select "tcp" --secure-select "tls"

  # Run specific test by name
  ${0} --test-select "rust-v0.56 x rust-v0.56"

  # Exclude specific baseline
  ${0} --baseline-ignore "https"

  # Traditional usage (still supported)
  ${0} --upload-bytes 5368709120 --download-bytes 5368709120

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

# Parse command line arguments
while [ $# -gt 0 ]; do
  case "${1}" in
    # Implementation filtering
    --impl-select) IMPL_SELECT="${2}"; shift 2 ;;
    --impl-ignore) IMPL_IGNORE="${2}"; shift 2 ;;

    # Baseline filtering (perf only)
    --baseline-select) BASELINE_SELECT="${2}"; shift 2 ;;
    --baseline-ignore) BASELINE_IGNORE="${2}"; shift 2 ;;

    # Component filtering
    --transport-select) TRANSPORT_SELECT="${2}"; shift 2 ;;
    --transport-ignore) TRANSPORT_IGNORE="${2}"; shift 2 ;;
    --secure-select) SECURE_SELECT="${2}"; shift 2 ;;
    --secure-ignore) SECURE_IGNORE="${2}"; shift 2 ;;
    --muxer-select) MUXER_SELECT="${2}"; shift 2 ;;
    --muxer-ignore) MUXER_IGNORE="${2}"; shift 2 ;;

    # Test name filtering
    --test-select) TEST_SELECT="${2}"; shift 2 ;;
    --test-ignore) TEST_IGNORE="${2}"; shift 2 ;;

    # Configuration options
    --upload-bytes) UPLOAD_BYTES="${2}"; shift 2 ;;
    --download-bytes) DOWNLOAD_BYTES="${2}"; shift 2 ;;
    --iterations) ITERATIONS="${2}"; shift 2 ;;
    --duration) DURATION_PER_ITERATION="${2}"; shift 2 ;;
    --latency-iterations) LATENCY_ITERATIONS="${2}"; shift 2 ;;
    --cache-dir) CACHE_DIR="${2}"; shift 2 ;;

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

    *)
      echo "Unknown option: ${1}"
      echo ""
      show_help
      exit 1
      ;;
  esac
done

# Generate test run key and test pass name
export TEST_TYPE="perf"
export TEST_RUN_KEY=$(compute_test_run_key \
  "${IMAGES_YAML}" \
  "${IMPL_SELECT}" \
  "${IMPL_IGNORE}" \
  "${BASELINE_SELECT}" \
  "${BASELINE_IGNORE}" \
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
# This loads the implementations and baselines from the images.yaml file and 
# prints them out nicely and exits. This is triggered by the `--list-images`
# command line argument
# =============================================================================

# List images
if [ "${LIST_IMAGES}" == "true" ]; then
  if [ ! -f "${IMAGES_YAML}" ]; then
    print_error "${IMAGES_YAML} not found"
    exit 1
  fi

  print_header "Available Docker Images"
  indent

  # Get and print implementations
  readarray -t all_image_ids < <(get_entity_ids "implementations")
  print_list "Implementations" all_image_ids

  println

  # Get and print baselines
  readarray -t all_baseline_ids < <(get_entity_ids "baselines")
  print_list "Baselines" all_baseline_ids

  println
  unindent
  exit 0
fi

# =============================================================================
# STEP 3.B: LIST TESTS AND EXIT
# -----------------------------------------------------------------------------
# This creates a temporary folder, runs the test matrix generation, then lists
# the baseline and main tests that are selected to run and which ones are
# ignored based on the environment and command line arguments. This is
# triggered by the `--list-tests` command line argument
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
  export TEST_IGNORE BASELINE_IGNORE TRANSPORT_IGNORE SECURE_IGNORE MUXER_IGNORE
  export UPLOAD_BYTES DOWNLOAD_BYTES
  export ITERATIONS DURATION_PER_ITERATION LATENCY_ITERATIONS
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
  println

  print_header "Test Selection..."
  indent

  # Get and print the selected baseline tests
  readarray -t selected_baseline_tests < <(get_entity_ids "baselines" "${TEMP_DIR}/test-matrix.yaml")
  print_list "Selected baseline tests" selected_baseline_tests

  println

  # Get and maybe print the ignored baseline tests
  readarray -t ignored_baseline_tests < <(get_entity_ids "ignoredBaselines" "${TEMP_DIR}/test-matrix.yaml")
  if [ "${SHOW_IGNORED}" == "true" ]; then
    print_list "Ignored baseline tests" ignored_baseline_tests
    println
  fi

  # Get and print the selected main tests
  readarray -t selected_main_tests < <(get_entity_ids "tests" "${TEMP_DIR}/test-matrix.yaml")
  print_list "Selected main tests" selected_main_tests

  println

  # Get and maybe print the ignored main tests
  readarray -t ignored_main_tests < <(get_entity_ids "ignoredTests" "${TEMP_DIR}/test-matrix.yaml")
  if [ "${SHOW_IGNORED}" == "true" ]; then
    print_list "Ignored main tests" ignored_main_tests
    println
  fi

  print_message "Total selected: ${#selected_baseline_tests[@]} baseline + ${#selected_main_tests[@]} main = $((${#selected_baseline_tests[@]} + ${#selected_main_tests[@]})) tests"
  print_message "Total ignored: ${#ignored_baseline_tests[@]} baseline + ${#ignored_main_tests[@]} main = $((${#ignored_baseline_tests[@]} + ${#ignored_main_tests[@]})) tests"
  println

  unindent
  rm -rf "${TEMP_DIR}"
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
    println
    print_error "Error: Missing required dependencies."
    print_message "Run '${0} --check-deps' to see details."
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

# Display filters (only if set)
[ -n "${IMPL_SELECT}" ] && print_message "Impl Select: ${IMPL_SELECT}"
[ -n "${IMPL_IGNORE}" ] && print_message "Impl Ignore: ${IMPL_IGNORE}"
[ -n "${BASELINE_SELECT}" ] && print_message "Baseline Select: ${BASELINE_SELECT}"
[ -n "${BASELINE_IGNORE}" ] && print_message "Baseline Ignore: ${BASELINE_IGNORE}"
[ -n "${TRANSPORT_SELECT}" ] && print_message "Transport Select: ${TRANSPORT_SELECT}"
[ -n "${TRANSPORT_IGNORE}" ] && print_message "Transport Ignore: ${TRANSPORT_IGNORE}"
[ -n "${SECURE_SELECT}" ] && print_message "Secure Select: ${SECURE_SELECT}"
[ -n "${SECURE_IGNORE}" ] && print_message "Secure Ignore: ${SECURE_IGNORE}"
[ -n "${MUXER_SELECT}" ] && print_message "Muxer Select: ${MUXER_SELECT}"
[ -n "${MUXER_IGNORE}" ] && print_message "Muxer Ignore: ${MUXER_IGNORE}"
[ -n "${TEST_SELECT}" ] && print_message "Test Select: ${TEST_SELECT}"
[ -n "${TEST_IGNORE}" ] && print_message "Test Ignore: ${TEST_IGNORE}"

print_message "Upload Bytes: $(numfmt --to=iec --suffix=B "${UPLOAD_BYTES}" 2>/dev/null || echo "${UPLOAD_BYTES} bytes")"
print_message "Download Bytes: $(numfmt --to=iec --suffix=B "${DOWNLOAD_BYTES}" 2>/dev/null || echo "${DOWNLOAD_BYTES} bytes")"
print_message "Iterations: ${ITERATIONS}"
print_message "Duration per Iteration: ${DURATION_PER_ITERATION}s"
print_message "Latency Iterations: ${LATENCY_ITERATIONS}"
print_message "Create Snapshot: ${CREATE_SNAPSHOT}"
print_message "Debug: ${DEBUG}"
print_message "Force Matrix Rebuild: ${FORCE_MATRIX_REBUILD}"
print_message "Force Image Rebuild: ${FORCE_IMAGE_REBUILD}"
println

# Set up the folder structure for the output
mkdir -p "${TEST_PASS_DIR}"/{logs,results,baseline,docker-compose}

# Generate inputs.yaml to capture the current environment and command line arguments
generate_inputs_yaml "${TEST_PASS_DIR}/inputs.yaml" "$TEST_TYPE" "${ORIGINAL_ARGS[@]}"

println
unindent

# Check dependencies for normal execution
print_header "Checking dependencies..."
indent
bash "${SCRIPT_LIB_DIR}/check-dependencies.sh" docker yq || {
  println
  print_error "Error: Missing required dependencies."
  print_message "Run '${0} --check-deps' to see details."
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
println

# Start timing
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
println

# =============================================================================
# STEP 6: PRINT TEST SELECTION
# -----------------------------------------------------------------------------
# This loads the test matrix data and prints it out. If AUTO_YES is not true,
# then prompt the user if they would like to continue.
# =============================================================================

# Display test selection and get confirmation
print_header "Test Selection..."
indent

# Get and print the selected baseline tests
readarray -t selected_baseline_tests < <(get_entity_ids "baselines" "${TEST_PASS_DIR}/test-matrix.yaml")
print_list "Selected baseline tests" selected_baseline_tests

println

# Get and maybe print the ignored baseline tests
readarray -t ignored_baseline_tests < <(get_entity_ids "ignoredBaselines" "${TEST_PASS_DIR}/test-matrix.yaml")
if [ "${SHOW_IGNORED}" == "true" ]; then
  print_list "Ignored baseline tests" ignored_baseline_tests
  println
fi

# Get and print the selected main tests
readarray -t selected_main_tests < <(get_entity_ids "tests" "${TEST_PASS_DIR}/test-matrix.yaml")
print_list "Selected main tests" selected_main_tests

println

# Get and maybe print the ignored main tests
readarray -t ignored_main_tests < <(get_entity_ids "ignoredTests" "${TEST_PASS_DIR}/test-matrix.yaml")
if [ "${SHOW_IGNORED}" == "true" ]; then
  print_list "Ignored main tests" ignored_main_tests
  println
fi

BASELINE_COUNT=${#selected_baseline_tests[@]}
TEST_COUNT=${#selected_main_tests[@]}
TOTAL_TESTS=$(("${BASELINE_COUNT}" + "${TEST_COUNT}"))

print_message "Total selected: ${BASELINE_COUNT} baseline + ${TEST_COUNT} main = ${TOTAL_TESTS} tests"
print_message "Total ignored: ${#ignored_baseline_tests[@]} baseline + ${#ignored_main_tests[@]} main = $((${#ignored_baseline_tests[@]} + ${#ignored_main_tests[@]})) tests"
println
unindent

# Get unique implementations from both baselines and main tests
REQUIRED_IMAGES=$(mktemp)
yq eval '.baselines[].dialer.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u > "${REQUIRED_IMAGES}" || true
yq eval '.baselines[].listener.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
yq eval '.tests[].dialer.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
yq eval '.tests[].listener.id' "${TEST_PASS_DIR}/test-matrix.yaml" 2>/dev/null | sort -u >> "${REQUIRED_IMAGES}" || true
sort -u "${REQUIRED_IMAGES}" -o "${REQUIRED_IMAGES}"
IMAGE_COUNT=$(wc -l < "${REQUIRED_IMAGES}")

# Prompt for confirmation unless auto-approved
indent
if [ "${AUTO_YES}" != true ]; then
  read -p "  Build ${IMAGE_COUNT} Docker images and execute ${TOTAL_TESTS} tests (${BASELINE_COUNT} baseline + ${TEST_COUNT} main)? (Y/n): " response
  response=${response:-Y}

  if [[ ! "${response}" =~ ^[Yy]$ ]]; then
    println
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
println
print_header "Building Docker images..."
indent

print_message "Building ${IMAGE_COUNT} required implementations"
println

# Build each required implementation using pipe-separated list
IMAGE_FILTER=$(cat "${REQUIRED_IMAGES}" | paste -sd'|' -)

# Build images from both baselines and implementations
build_images_from_section "baselines" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"

print_success "All images built successfully"

rm -f "${REQUIRED_IMAGES}"
unindent
println

# =============================================================================
# STEP 8: RUN TESTS
# -----------------------------------------------------------------------------
# This starts global services (e.g. Redis), then runs the baseline tests
# followed by the main tests and then stops the global services.
# =============================================================================

# Start global services
print_header "Staring global services..."
indent
start_redis_service "perf-network" "perf-redis" || {
  print_error "Starting global services failed"
  unindent
  return 1
}
unindent
println

# Run baseline tests FIRST (before main tests)
print_header "Running baseline tests... (1 worker)"
indent

# Run a single baseline test with serialized output
run_baseline_test() {
  local index="${1}"
  local name=$(yq eval ".baselines[${index}].id" "${TEST_PASS_DIR}/test-matrix.yaml")

  source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"

  # Run baseline test
  if bash "${SCRIPT_DIR}/run-single-test.sh" "${index}" "baselines" "${TEST_PASS_DIR}/baseline-results.yaml.tmp"; then
    result="[SUCCESS]"
    exit_code=0
  else
    result="[FAILED]"
    exit_code=1
  fi

  # Serialize the message printing using flock (prevents interleaved output)
  (
    flock -x 200
    print_message "[$((index + 1))/${BASELINE_COUNT}] ${name}...${result}"
  ) 200>/tmp/perf-test-output.lock

  return ${exit_code}
}

if [ "${BASELINE_COUNT}" -eq 0 ]; then
    print_message "No baseline tests selected"
else
  # Initialize baseline results file
  > "${TEST_PASS_DIR}/baseline-results.yaml.tmp"

  # Export variables needed by run_baseline_test
  export BASELINE_COUNT
  export -f run_baseline_test

  # Run baseline tests (sequential for accurate performance measurements)
  seq 0 $((BASELINE_COUNT - 1)) | xargs -P "${WORKER_COUNT}" -I {} bash -c 'run_baseline_test {}' || true
fi

unindent
println

# Run main performance tests
print_header "Running tests... (1 worker)"
indent

# Run a single test with serialized output
run_test() {
  local index="${1}"
  local name=$(yq eval ".tests[${index}].id" "${TEST_PASS_DIR}/test-matrix.yaml")

  source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"

  # Run test
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
  ) 200>/tmp/perf-test-output.lock

  return ${exit_code}
}

if [ "${TEST_COUNT}" -eq 0 ]; then
    print_message "No tests selected"
else
  # Initialize results file
  > "${TEST_PASS_DIR}/results.yaml.tmp"

  # Export variables needed by run_test
  export TEST_COUNT
  export -f run_test

  # Run tests (sequential for accurate performance measurements)
  seq 0 $((TEST_COUNT - 1)) | xargs -P "${WORKER_COUNT}" -I {} bash -c 'run_test {}' || true
fi

unindent
println

# Stop global services
print_header "Stopping global services..."
indent
stop_redis_service "perf-network" "perf-redis" || {
  print_error "Stopping global services failed"
  unindent
  return 1
}
unindent
println

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

# Count pass/fail from baseline results
BASELINE_PASSED=0
BASELINE_FAILED=0
if [ -f "${TEST_PASS_DIR}/baseline-results.yaml.tmp" ]; then
    BASELINE_PASSED=$(grep -c "status: pass" "${TEST_PASS_DIR}/baseline-results.yaml.tmp" || true)
    BASELINE_FAILED=$(grep -c "status: fail" "${TEST_PASS_DIR}/baseline-results.yaml.tmp" || true)
    BASELINE_PASSED=${BASELINE_PASSED:-0}
    BASELINE_FAILED=${BASELINE_FAILED:-0}
fi

# Count pass/fail from main test results
PASSED=0
FAILED=0
if [ -f "${TEST_PASS_DIR}/results.yaml.tmp" ]; then
    PASSED=$(grep -c "status: pass" "${TEST_PASS_DIR}/results.yaml.tmp" || true)
    FAILED=$(grep -c "status: fail" "${TEST_PASS_DIR}/results.yaml.tmp" || true)
fi

# Total counts
TOTAL_PASSED=$((BASELINE_PASSED + PASSED))
TOTAL_FAILED=$((BASELINE_FAILED + FAILED))
# TOTAL_TESTS already defined earlier in script

# Generate final results.yaml
cat > "${TEST_PASS_DIR}/results.yaml" <<EOF
metadata:
  testPass: ${TEST_PASS_NAME}
  startedAt: $(format_timestamp "${TEST_START_TIME}")
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration: ${TEST_DURATION}s
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: ${WORKER_COUNT}

summary:
  totalBaselines: ${BASELINE_COUNT}
  baselinesPassed: ${BASELINE_PASSED}
  baselinesFailed: ${BASELINE_FAILED}
  totalTests: ${TEST_COUNT}
  testsPassed: ${PASSED}
  testsFailed: ${FAILED}
  totalAll: ${TOTAL_TESTS}
  passedAll: ${TOTAL_PASSED}
  failedAll: ${TOTAL_FAILED}

baselineResults:
EOF

# Append baseline results if they exist
if [ -f "${TEST_PASS_DIR}/baseline-results.yaml.tmp" ]; then
    cat "${TEST_PASS_DIR}/baseline-results.yaml.tmp" >> "${TEST_PASS_DIR}/results.yaml"
    rm "${TEST_PASS_DIR}/baseline-results.yaml.tmp"
fi

cat >> "${TEST_PASS_DIR}/results.yaml" <<EOF

testResults:
EOF

# Append main test results if they exist
if [ -f "${TEST_PASS_DIR}/results.yaml.tmp" ]; then
    cat "${TEST_PASS_DIR}/results.yaml.tmp" >> "${TEST_PASS_DIR}/results.yaml"
    rm "${TEST_PASS_DIR}/results.yaml.tmp"
fi

print_message "Results:"
indent
print_message "Total: ${TOTAL_TESTS} (${BASELINE_COUNT} baseline + ${TEST_COUNT} main)"
print_success "Passed: ${TOTAL_PASSED}"
print_error "Failed: ${TOTAL_FAILED}"

# List failed tests if any
if [ "${TOTAL_FAILED}" -gt 0 ]; then
  readarray -t FAILED_TESTS < <(yq eval '.baselineResults[]?, .testResults[]? | select(.status == "fail") | .name' "${TEST_PASS_DIR}/results.yaml" 2>/dev/null || true)
  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    for test_name in "${FAILED_TESTS[@]}"; do
      echo "    - ${test_name}"
    done
  fi
fi

unindent
println

# Display execution time
HOURS=$((TEST_DURATION / 3600))
MINUTES=$(((TEST_DURATION % 3600) / 60))
SECONDS=$((TEST_DURATION % 60))
print_message "$(printf "Total time: %02d:%02d:%02d\n" "${HOURS}" "${MINUTES}" "${SECONDS}")"
println

# Display status message
if [ "${TOTAL_FAILED}" -eq 0 ]; then
  print_success "All tests passed!"
  EXIT_FINAL=0
else
  print_error "${FAILED} test(s) failed"
  EXIT_FINAL=1
fi

unindent
println

# =============================================================================
# STEP 10: GENERATE RESULTS DASHBOARD
# -----------------------------------------------------------------------------
# This creates the Markdown version for injecting into the README.md file for
# this test. If `pandoc` is installed, an HTML version is gnerated. If
# `gnuplot` is installed, box plot diagrams are also generated.
# =============================================================================

# Generate results dashboard
print_header "Generating results dashboard..."
indent

print_success "Generated ${TEST_PASS_DIR}/results.yaml"
bash "${SCRIPT_DIR}/generate-dashboard.sh" || {
  print_error "Dashboard generation failed"
}
println
print_success "Dashboard generation complete"
unindent
println

# Generate box plots (optional - requires gnuplot)
print_header "Generating box plots..."
indent

# Check if gnuplot is available
if command -v gnuplot &> /dev/null; then
  bash "${SCRIPT_DIR}/generate-boxplot.sh" "${TEST_PASS_DIR}/results.yaml" "${TEST_PASS_DIR}" || {
    print_error "Box plot generation failed"
  }
else
  print_error "gnuplot not found - skipping box plot generation"
  indent
  print_message "Install: apt-get install gnuplot"
  unindent
fi
unindent
println

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
