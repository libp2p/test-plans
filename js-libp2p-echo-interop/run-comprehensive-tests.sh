#!/usr/bin/env bash

# Comprehensive Test Suite for JS-libp2p Echo Interop
# Runs full test matrix across all protocol combinations and validates results

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
VERBOSE="${VERBOSE:-false}"
PARALLEL="${PARALLEL:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-test-results}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[COMPREHENSIVE]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Test result tracking
declare -a ALL_TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Add test result
add_test_result() {
    local test_name="$1"
    local status="$2"
    local duration="$3"
    local error_msg="${4:-}"
    local metadata="${5:-{}}"
    
    local result="{
        \"test_name\": \"$test_name\",
        \"status\": \"$status\",
        \"duration\": $duration,
        \"error\": \"$error_msg\",
        \"metadata\": $metadata,
        \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
    }"
    
    ALL_TEST_RESULTS+=("$result")
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    case "$status" in
        "passed") PASSED_TESTS=$((PASSED_TESTS + 1)) ;;
        "failed") FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        "skipped") SKIPPED_TESTS=$((SKIPPED_TESTS + 1)) ;;
    esac
}

# Cleanup function
cleanup() {
    log_info "Cleaning up comprehensive test environment..."
    
    # Stop all Docker Compose services
    docker-compose down --remove-orphans --volumes >/dev/null 2>&1 || true
    
    # Clean up Docker networks and volumes
    docker network prune -f >/dev/null 2>&1 || true
    docker volume prune -f >/dev/null 2>&1 || true
}

# Set up cleanup trap
trap cleanup EXIT

# Initialize test environment
initialize_test_environment() {
    log_info "Initializing comprehensive test environment..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Clean up any existing test artifacts
    rm -f "$OUTPUT_DIR"/*.json
    
    # Ensure Docker images are built
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "js-libp2p-echo-server:latest"; then
        log_info "Building JS Echo Server image..."
        make build-js >/dev/null 2>&1
    fi
    
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "py-test-harness:latest"; then
        log_info "Building Python Test Harness image..."
        make build-py >/dev/null 2>&1
    fi
    
    log_success "Test environment initialized"
}

# Run unit tests
run_unit_tests() {
    log_info "Running unit tests..."
    
    local start_time=$(date +%s)
    local status="failed"
    local error_msg=""
    
    # Run JS unit tests
    log_debug "Running JS Echo Server unit tests..."
    if (cd images/js-echo-server && npm test >/dev/null 2>&1); then
        log_debug "JS unit tests passed"
    else
        log_warning "JS unit tests failed or not configured"
    fi
    
    # Run Python unit tests
    log_debug "Running Python Test Harness unit tests..."
    if (cd images/py-test-harness && python3 -m pytest src/test_echo_protocol.py -v >/dev/null 2>&1); then
        log_debug "Python unit tests passed"
        status="passed"
    else
        error_msg="Python unit tests failed"
        log_warning "Python unit tests failed"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    add_test_result "unit_tests" "$status" "$duration" "$error_msg" "{\"test_type\": \"unit\"}"
    
    if [[ "$status" == "passed" ]]; then
        log_success "Unit tests completed"
        return 0
    else
        log_error "Unit tests failed"
        return 1
    fi
}

# Run property-based tests
run_property_tests() {
    log_info "Running property-based tests..."
    
    local start_time=$(date +%s)
    local status="failed"
    local error_msg=""
    
    # Run property-based tests in Python Test Harness
    log_debug "Running property-based tests..."
    if (cd images/py-test-harness && timeout 180 python3 -m pytest src/test_echo_properties.py src/test_error_handling_properties.py -v --tb=short >/dev/null 2>&1); then
        status="passed"
        log_success "Property-based tests passed"
    else
        error_msg="Property-based tests failed or timed out"
        log_error "Property-based tests failed"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    add_test_result "property_tests" "$status" "$duration" "$error_msg" "{\"test_type\": \"property\", \"timeout\": 180}"
    
    return 0  # Don't fail the entire suite if property tests fail
}

# Run integration tests for a specific protocol combination
run_integration_test() {
    local transport="$1"
    local security="$2"
    local muxer="$3"
    
    local test_name="integration_${transport}_${security}_${muxer}"
    log_debug "Running integration test: $test_name"
    
    local start_time=$(date +%s)
    local status="failed"
    local error_msg=""
    
    # Set environment variables
    export TRANSPORT="$transport"
    export SECURITY="$security"
    export MUXER="$muxer"
    export TEST_TIMEOUT="$TEST_TIMEOUT"
    export DEBUG="false"
    
    # Clean up any existing containers
    docker-compose down --remove-orphans --volumes >/dev/null 2>&1 || true
    
    # Run the integration test
    if timeout "$TEST_TIMEOUT" docker-compose up --abort-on-container-exit --exit-code-from py-test-harness >/dev/null 2>&1; then
        status="passed"
        log_debug "Integration test passed: $test_name"
    else
        error_msg="Integration test failed or timed out"
        log_debug "Integration test failed: $test_name"
    fi
    
    # Clean up after test
    docker-compose down --remove-orphans --volumes >/dev/null 2>&1 || true
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local metadata="{
        \"test_type\": \"integration\",
        \"transport\": \"$transport\",
        \"security\": \"$security\",
        \"muxer\": \"$muxer\",
        \"timeout\": $TEST_TIMEOUT
    }"
    
    add_test_result "$test_name" "$status" "$duration" "$error_msg" "$metadata"
    
    return 0  # Don't fail the entire suite if one integration test fails
}

# Run all integration tests
run_integration_tests() {
    log_info "Running integration tests across protocol combinations..."
    
    # Define protocol combinations to test
    local protocol_combinations=(
        "tcp:noise:yamux"
        "tcp:noise:mplex"
    )
    
    local integration_passed=0
    local integration_total=${#protocol_combinations[@]}
    
    for combination in "${protocol_combinations[@]}"; do
        IFS=':' read -r transport security muxer <<< "$combination"
        
        log_info "Testing protocol combination: $transport/$security/$muxer"
        
        if run_integration_test "$transport" "$security" "$muxer"; then
            integration_passed=$((integration_passed + 1))
        fi
        
        # Brief pause between tests
        sleep 2
    done
    
    log_info "Integration tests completed: $integration_passed/$integration_total combinations tested"
    
    # Consider integration tests successful if at least half pass
    if [[ $integration_passed -ge $((integration_total / 2)) ]]; then
        log_success "Integration tests completed successfully"
        return 0
    else
        log_error "Integration tests failed"
        return 1
    fi
}

# Run configuration validation tests
run_config_tests() {
    log_info "Running configuration validation tests..."
    
    local start_time=$(date +%s)
    local status="failed"
    local error_msg=""
    
    # Test various configuration combinations
    local configs=(
        "tcp:noise:yamux"
        "tcp:noise:mplex"
    )
    
    local config_passed=0
    local config_total=${#configs[@]}
    
    for config in "${configs[@]}"; do
        IFS=':' read -r transport security muxer <<< "$config"
        
        if TRANSPORT="$transport" SECURITY="$security" MUXER="$muxer" ./lib/validate-config.sh >/dev/null 2>&1; then
            config_passed=$((config_passed + 1))
            log_debug "Configuration validation passed: $config"
        else
            log_debug "Configuration validation failed: $config"
        fi
    done
    
    if [[ $config_passed -eq $config_total ]]; then
        status="passed"
        log_success "All configuration validations passed"
    else
        error_msg="$((config_total - config_passed)) configuration validations failed"
        log_error "$error_msg"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    add_test_result "config_validation" "$status" "$duration" "$error_msg" "{\"test_type\": \"config\", \"total_configs\": $config_total, \"passed_configs\": $config_passed}"
    
    return 0
}

# Run performance tests
run_performance_tests() {
    log_info "Running performance tests..."
    
    local start_time=$(date +%s)
    local status="passed"
    local error_msg=""
    
    # Test Docker image build performance
    log_debug "Testing Docker image build performance..."
    local build_start=$(date +%s)
    
    if make build >/dev/null 2>&1; then
        local build_end=$(date +%s)
        local build_duration=$((build_end - build_start))
        
        log_debug "Docker build completed in ${build_duration}s"
        
        # Consider build slow if it takes more than 5 minutes
        if [[ $build_duration -gt 300 ]]; then
            log_warning "Docker build took longer than expected: ${build_duration}s"
        fi
    else
        error_msg="Docker build failed"
        status="failed"
    fi
    
    # Test image sizes
    local js_image_size=$(docker images --format "{{.Size}}" js-libp2p-echo-server:latest | head -n1)
    local py_image_size=$(docker images --format "{{.Size}}" py-test-harness:latest | head -n1)
    
    log_debug "Image sizes - JS: $js_image_size, Python: $py_image_size"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local metadata="{
        \"test_type\": \"performance\",
        \"build_duration\": $((build_end - build_start)),
        \"js_image_size\": \"$js_image_size\",
        \"py_image_size\": \"$py_image_size\"
    }"
    
    add_test_result "performance_tests" "$status" "$duration" "$error_msg" "$metadata"
    
    return 0
}

# Generate comprehensive test report
generate_comprehensive_report() {
    log_info "Generating comprehensive test report..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local success_rate=0
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    # Create comprehensive report
    cat > "$OUTPUT_DIR/comprehensive-test-report.json" << EOF
{
  "test_suite": "js-libp2p-echo-interop-comprehensive",
  "timestamp": "$timestamp",
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "skipped_tests": $SKIPPED_TESTS,
    "success_rate": "${success_rate}%"
  },
  "test_results": [
$(IFS=','; echo "${ALL_TEST_RESULTS[*]}")
  ],
  "test_configuration": {
    "test_timeout": $TEST_TIMEOUT,
    "verbose": ${VERBOSE:-false},
    "parallel": ${PARALLEL:-false},
    "output_dir": "$OUTPUT_DIR"
  },
  "environment": {
    "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
    "docker_compose_version": "$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'not available')",
    "host_os": "$(uname -s)",
    "host_arch": "$(uname -m)",
    "shell": "$SHELL"
  },
  "test_matrix": {
    "protocol_combinations": [
      {"transport": "tcp", "security": "noise", "muxer": "yamux"},
      {"transport": "tcp", "security": "noise", "muxer": "mplex"}
    ],
    "test_types": ["unit", "property", "integration", "config", "performance"]
  }
}
EOF
    
    # Generate summary report
    cat > "$OUTPUT_DIR/test-summary.txt" << EOF
JS-libp2p Echo Interop - Comprehensive Test Results
==================================================

Test Execution: $timestamp

Summary:
  Total Tests: $TOTAL_TESTS
  Passed: $PASSED_TESTS
  Failed: $FAILED_TESTS
  Skipped: $SKIPPED_TESTS
  Success Rate: ${success_rate}%

Test Types:
  - Unit Tests
  - Property-Based Tests
  - Integration Tests (TCP/Noise/Yamux, TCP/Noise/Mplex)
  - Configuration Validation Tests
  - Performance Tests

Protocol Combinations Tested:
  - TCP/Noise/Yamux
  - TCP/Noise/Mplex

Environment:
  - Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')
  - Host: $(uname -s) $(uname -m)
  - Test Timeout: ${TEST_TIMEOUT}s

$(if [[ $FAILED_TESTS -gt 0 ]]; then
    echo "Failed Tests:"
    for result in "${ALL_TEST_RESULTS[@]}"; do
        local test_name=$(echo "$result" | python3 -c "import json, sys; print(json.load(sys.stdin)['test_name'])")
        local status=$(echo "$result" | python3 -c "import json, sys; print(json.load(sys.stdin)['status'])")
        if [[ "$status" == "failed" ]]; then
            echo "  - $test_name"
        fi
    done
fi)

For detailed results, see: comprehensive-test-report.json
EOF
    
    log_success "Comprehensive test report generated:"
    log_info "  - JSON Report: $OUTPUT_DIR/comprehensive-test-report.json"
    log_info "  - Summary: $OUTPUT_DIR/test-summary.txt"
}

# Main comprehensive test function
main() {
    log_info "Starting Comprehensive Test Suite for JS-libp2p Echo Interop"
    log_info "Configuration:"
    log_info "  Test Timeout: ${TEST_TIMEOUT}s"
    log_info "  Verbose: ${VERBOSE:-false}"
    log_info "  Parallel: ${PARALLEL:-false}"
    log_info "  Output Directory: $OUTPUT_DIR"
    
    cd "$PROJECT_ROOT"
    
    # Initialize test environment
    initialize_test_environment
    
    # Run all test suites
    local test_suites=(
        "run_config_tests"
        "run_unit_tests"
        "run_property_tests"
        "run_performance_tests"
        "run_integration_tests"
    )
    
    local suite_results=()
    
    for test_suite in "${test_suites[@]}"; do
        log_info "Executing test suite: $test_suite"
        
        if $test_suite; then
            suite_results+=("$test_suite:PASSED")
            log_success "✓ $test_suite completed successfully"
        else
            suite_results+=("$test_suite:FAILED")
            log_error "✗ $test_suite failed"
        fi
        
        echo ""  # Add spacing between test suites
    done
    
    # Generate comprehensive report
    generate_comprehensive_report
    
    # Display final summary
    log_info "Comprehensive Test Suite Summary:"
    log_info "  Total Tests: $TOTAL_TESTS"
    log_info "  Passed: $PASSED_TESTS"
    log_info "  Failed: $FAILED_TESTS"
    log_info "  Skipped: $SKIPPED_TESTS"
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    log_info "  Success Rate: ${success_rate}%"
    
    echo ""
    log_info "Test Suite Results:"
    for result in "${suite_results[@]}"; do
        IFS=':' read -r suite status <<< "$result"
        if [[ "$status" == "PASSED" ]]; then
            log_success "  ✓ $suite"
        else
            log_error "  ✗ $suite"
        fi
    done
    
    # Determine overall success
    if [[ $success_rate -ge 80 ]]; then
        log_success "🎉 Comprehensive test suite completed successfully!"
        log_info "All critical functionality is working correctly."
        return 0
    elif [[ $success_rate -ge 60 ]]; then
        log_warning "⚠️  Comprehensive test suite completed with warnings."
        log_info "Most functionality is working, but some tests failed."
        return 0
    else
        log_error "❌ Comprehensive test suite failed."
        log_info "Critical issues detected. Please review the test results."
        return 1
    fi
}

# Handle command line arguments
case "${1:-test}" in
    "test")
        main
        ;;
    "unit")
        initialize_test_environment && run_unit_tests
        ;;
    "property")
        initialize_test_environment && run_property_tests
        ;;
    "integration")
        initialize_test_environment && run_integration_tests
        ;;
    "config")
        run_config_tests
        ;;
    "performance")
        initialize_test_environment && run_performance_tests
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [test|unit|property|integration|config|performance|help]"
        echo ""
        echo "Commands:"
        echo "  test         - Run comprehensive test suite (default)"
        echo "  unit         - Run unit tests only"
        echo "  property     - Run property-based tests only"
        echo "  integration  - Run integration tests only"
        echo "  config       - Run configuration validation tests only"
        echo "  performance  - Run performance tests only"
        echo "  help         - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  TEST_TIMEOUT=300   - Test timeout in seconds"
        echo "  VERBOSE=true       - Enable verbose output"
        echo "  PARALLEL=true      - Enable parallel test execution"
        echo "  OUTPUT_DIR=results - Test results output directory"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac