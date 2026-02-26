#!/bin/bash

# run in strict failure mode
set -euo pipefail

#                                 ╔═══╗ ╔═══╗ ╔╗  ╔╗ ╔═══╗
# ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╔══╝ ║╔═╗║ ║║  ║║ ║╔═╗║ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
# ═══════════════════════════════ ║╚══╗ ║║ ║║ ║╚══╝║ ║║ ║║ ═════════════════════════════════
# ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚═══╝ ╚╝ ╚╝ ╚════╝ ╚╝ ╚╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔

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
load_inputs_yaml_args_inline() {
  local inputs_file="${1:-inputs.yaml}"

  # Look for the inputs file if it exists
  if [ ! -f "${inputs_file}" ]; then
    return 1
  fi

  # Load the command line arguments from the inputs file
  readarray -t LOADED_ARGS < <(yq eval '.commandLineArguments[]' "${inputs_file}" 2>/dev/null)

  return 0
}

# Try to load inputs.yaml if it exists
LOADED_ARGS=()
if load_inputs_yaml_inline "inputs.yaml"; then
  load_inputs_yaml_args_inline "inputs.yaml"
fi

# =============================================================================
# STEP 2: ENVIRONMENT SETUP
# =============================================================================

# Set up paths
export TEST_ROOT="$(pwd)"
export SCRIPT_LIB_DIR="${TEST_ROOT}/../lib"
export CACHE_DIR="${CACHE_DIR:-/srv/cache}"
export IMAGES_YAML="${TEST_ROOT}/images.yaml"

# Test configuration
export TEST_TYPE="echo"
export WORKERS="${WORKERS:-$(nproc)}"
export DEBUG="${DEBUG:-false}"

# Filter configuration
export IMPL_SELECT="${IMPL_SELECT:-}"
export IMPL_IGNORE="${IMPL_IGNORE:-}"
export TRANSPORT_SELECT="${TRANSPORT_SELECT:-}"
export TRANSPORT_IGNORE="${TRANSPORT_IGNORE:-}"
export SECURE_SELECT="${SECURE_SELECT:-}"
export SECURE_IGNORE="${SECURE_IGNORE:-}"
export MUXER_SELECT="${MUXER_SELECT:-}"
export MUXER_IGNORE="${MUXER_IGNORE:-}"
export TEST_SELECT="${TEST_SELECT:-}"
export TEST_IGNORE="${TEST_IGNORE:-}"

# =============================================================================
# STEP 3: ARGUMENT PARSING
# =============================================================================

# Merge loaded args with command line args (command line takes precedence)
ALL_ARGS=("${LOADED_ARGS[@]}" "$@")

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
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
    --test-select)
      TEST_SELECT="$2"
      shift 2
      ;;
    --test-ignore)
      TEST_IGNORE="$2"
      shift 2
      ;;
    --workers)
      WORKERS="$2"
      shift 2
      ;;
    --debug)
      DEBUG="true"
      shift
      ;;
    --check-deps)
      exec "${SCRIPT_LIB_DIR}/check-dependencies.sh"
      ;;
    --help|-h)
      echo "Echo Protocol Interoperability Tests"
      echo ""
      echo "Usage: $0 [options]"
      echo ""
      echo "Filtering Options:"
      echo "  --impl-select FILTER      Select implementations (e.g., 'js-libp2p')"
      echo "  --impl-ignore FILTER      Ignore implementations (e.g., '!py-libp2p')"
      echo "  --transport-select FILTER Select transports (e.g., 'tcp')"
      echo "  --transport-ignore FILTER Ignore transports"
      echo "  --secure-select FILTER    Select secure channels (e.g., 'noise')"
      echo "  --secure-ignore FILTER    Ignore secure channels"
      echo "  --muxer-select FILTER     Select muxers (e.g., 'yamux')"
      echo "  --muxer-ignore FILTER     Ignore muxers"
      echo "  --test-select FILTER      Select specific tests"
      echo "  --test-ignore FILTER      Ignore specific tests"
      echo ""
      echo "Execution Options:"
      echo "  --workers N               Number of parallel workers (default: $(nproc))"
      echo "  --debug                   Enable debug output"
      echo ""
      echo "Utility Options:"
      echo "  --check-deps              Check system dependencies"
      echo "  --help, -h                Show this help"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Run all tests"
      echo "  $0 --impl-select js-libp2p           # Test only js-libp2p"
      echo "  $0 --transport-ignore '!tcp'         # Test only TCP transport"
      echo "  $0 --debug --workers 1               # Debug mode, single worker"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# =============================================================================
# STEP 4: DEPENDENCY CHECKS
# =============================================================================

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-common-init.sh"
source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"

# Check dependencies
"${SCRIPT_LIB_DIR}/check-dependencies.sh" || exit 1

# =============================================================================
# STEP 5: GENERATE INPUTS.YAML
# =============================================================================

source "${SCRIPT_LIB_DIR}/lib-inputs-yaml.sh"
generate_inputs_yaml "${TEST_ROOT}/inputs.yaml" "${TEST_TYPE}" "${ORIGINAL_ARGS[@]}"

# =============================================================================
# STEP 6: GENERATE TEST MATRIX
# =============================================================================

print_message "Generating Echo protocol test matrix..."
"${TEST_ROOT}/lib/generate-tests.sh"

# =============================================================================
# STEP 7: BUILD IMAGES
# =============================================================================

print_message "Building Docker images..."
source "${SCRIPT_LIB_DIR}/lib-image-building.sh"
build_all_images

# =============================================================================
# STEP 8: GENERATE DOCKER COMPOSE FILES
# =============================================================================

print_message "Generating Docker Compose files..."
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"

CACHE_KEY=$(compute_test_cache_key)
TEST_MATRIX_FILE="${CACHE_DIR}/test-matrix/echo-${CACHE_KEY}.yaml"

# Generate compose files for each test
while IFS= read -r test_name; do
    COMPOSE_FILE="${CACHE_DIR}/test-docker-compose/echo-${CACHE_KEY}-${test_name}.yaml"
    mkdir -p "$(dirname "${COMPOSE_FILE}")"
    
    # Generate basic compose file (simplified for echo tests)
    cat > "${COMPOSE_FILE}" << EOF
version: '3.8'
services:
  redis:
    image: redis:alpine
    networks:
      - echo-test
  
  server:
    image: \${SERVER_IMAGE}
    depends_on:
      - redis
    environment:
      - REDIS_ADDR=redis://redis:6379
    networks:
      - echo-test
  
  client:
    image: \${CLIENT_IMAGE}
    depends_on:
      - server
    environment:
      - REDIS_ADDR=redis://redis:6379
    networks:
      - echo-test

networks:
  echo-test:
    driver: bridge
EOF
done < <(yq eval '.tests[].name' "${TEST_MATRIX_FILE}")

# =============================================================================
# STEP 9: RUN TESTS
# =============================================================================

print_message "Running Echo protocol tests..."

# Create results directory
RESULTS_DIR="${TEST_ROOT}/results"
mkdir -p "${RESULTS_DIR}"

# Run tests in parallel
export -f run_single_test
readarray -t test_names < <(yq eval '.tests[].name' "${TEST_MATRIX_FILE}")

if [[ "${WORKERS}" -eq 1 ]] || [[ "${DEBUG}" == "true" ]]; then
    # Sequential execution for debugging
    for test_name in "${test_names[@]}"; do
        run_single_test "${test_name}"
    done
else
    # Parallel execution
    printf '%s\n' "${test_names[@]}" | xargs -P "${WORKERS}" -I {} bash -c 'run_single_test "$@"' _ {}
fi

# =============================================================================
# STEP 10: GENERATE DASHBOARD
# =============================================================================

print_message "Generating test dashboard..."
"${TEST_ROOT}/lib/generate-dashboard.sh" "${RESULTS_DIR}"

# =============================================================================
# STEP 11: SUMMARY
# =============================================================================

TOTAL_TESTS=$(find "${RESULTS_DIR}" -name "*.json" | wc -l)
PASSED_TESTS=$(find "${RESULTS_DIR}" -name "*.json" -exec grep -l '"result": "PASS"' {} \; | wc -l)
FAILED_TESTS=$((TOTAL_TESTS - PASSED_TESTS))

print_message "Echo Protocol Test Results:"
print_message "  Total: ${TOTAL_TESTS}"
print_message "  Passed: ${PASSED_TESTS}"
print_message "  Failed: ${FAILED_TESTS}"

if [[ "${FAILED_TESTS}" -gt 0 ]]; then
    print_message "❌ Some tests failed - check ${RESULTS_DIR}/echo-dashboard.html"
    exit 1
else
    print_message "✅ All tests passed!"
    exit 0
fi

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

run_single_test() {
    local test_name="$1"
    "${TEST_ROOT}/lib/run-single-test.sh" "${test_name}" > "${RESULTS_DIR}/${test_name}.json"
}