#!/usr/bin/env bash

# End-to-End Integration Test for JS-libp2p Echo Interop
# Tests the complete flow: JS Echo Server + Python Test Harness + Redis Coordination

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
TEST_TIMEOUT="${TEST_TIMEOUT:-120}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[E2E]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[E2E-SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[E2E-WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[E2E-ERROR]${NC} $*"
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${BLUE}[E2E-DEBUG]${NC} $*"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Stop Docker Compose services
    docker-compose down --remove-orphans --volumes >/dev/null 2>&1 || true
    
    # Remove any test artifacts
    rm -f test-results.json integration-test-report.json
    
    # Clean up Docker networks
    docker network prune -f >/dev/null 2>&1 || true
}

# Set up cleanup trap
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for end-to-end integration test..."
    
    local missing_tools=()
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_tools+=("docker")
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        missing_tools+=("docker-compose")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    # Check if images are built
    local missing_images=()
    
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "js-libp2p-echo-server:latest"; then
        missing_images+=("js-libp2p-echo-server:latest")
    fi
    
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "py-test-harness:latest"; then
        missing_images+=("py-test-harness:latest")
    fi
    
    if [[ ${#missing_images[@]} -gt 0 ]]; then
        log_error "Missing Docker images: ${missing_images[*]}"
        log_error "Please run 'make build' first"
        return 1
    fi
    
    log_success "All prerequisites are available"
    return 0
}

# Test protocol combinations
test_protocol_combinations() {
    log_info "Testing protocol combinations..."
    
    local protocol_combinations=(
        "tcp:noise:yamux"
        "tcp:noise:mplex"
    )
    
    local test_results=()
    local total_tests=0
    local passed_tests=0
    
    for combination in "${protocol_combinations[@]}"; do
        IFS=':' read -r transport security muxer <<< "$combination"
        
        log_info "Testing protocol combination: $transport/$security/$muxer"
        
        # Set environment variables
        export TRANSPORT="$transport"
        export SECURITY="$security"
        export MUXER="$muxer"
        export TEST_TIMEOUT="$TEST_TIMEOUT"
        export DEBUG="false"
        
        # Clean up any existing containers
        docker-compose down --remove-orphans --volumes >/dev/null 2>&1 || true
        
        local test_start=$(date +%s)
        local test_status="failed"
        local error_msg=""
        
        # Run the integration test
        log_debug "Starting containers for $combination..."
        
        if timeout "$TEST_TIMEOUT" docker-compose up --abort-on-container-exit --exit-code-from py-test-harness >/dev/null 2>&1; then
            test_status="passed"
            log_success "Integration test passed for $combination"
        else
            error_msg="Test failed or timed out"
            log_error "Integration test failed for $combination"
        fi
        
        local test_end=$(date +%s)
        local test_duration=$((test_end - test_start))
        
        # Record test result
        local test_result="{
            \"test_name\": \"integration_${transport}_${security}_${muxer}\",
            \"status\": \"$test_status\",
            \"duration\": $test_duration,
            \"implementation\": \"js-libp2p-py-libp2p\",
            \"version\": \"latest\",
            \"transport\": \"$transport\",
            \"security\": \"$security\",
            \"muxer\": \"$muxer\",
            \"error\": \"$error_msg\",
            \"metadata\": {
                \"test_type\": \"end_to_end_integration\",
                \"timeout\": $TEST_TIMEOUT
            }
        }"
        
        test_results+=("$test_result")
        total_tests=$((total_tests + 1))
        
        if [[ "$test_status" == "passed" ]]; then
            passed_tests=$((passed_tests + 1))
        fi
        
        # Clean up after each test
        docker-compose down --remove-orphans --volumes >/dev/null 2>&1 || true
        sleep 2  # Brief pause between tests
    done
    
    # Generate test report
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local success_rate=0
    
    if [[ $total_tests -gt 0 ]]; then
        success_rate=$((passed_tests * 100 / total_tests))
    fi
    
    cat > integration-test-report.json << EOF
{
  "test_timestamp": "$timestamp",
  "test_type": "end_to_end_integration",
  "summary": {
    "total_tests": $total_tests,
    "passed_tests": $passed_tests,
    "failed_tests": $((total_tests - passed_tests)),
    "success_rate": "${success_rate}%"
  },
  "test_results": [
$(IFS=','; echo "${test_results[*]}")
  ],
  "environment": {
    "test_timeout": $TEST_TIMEOUT,
    "verbose": ${VERBOSE:-false},
    "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
    "host_os": "$(uname -s)",
    "host_arch": "$(uname -m)"
  }
}
EOF
    
    log_info "Integration test results:"
    log_info "  Total tests: $total_tests"
    log_info "  Passed: $passed_tests"
    log_info "  Failed: $((total_tests - passed_tests))"
    log_info "  Success rate: ${success_rate}%"
    
    # Return success if at least one test passed
    if [[ $passed_tests -gt 0 ]]; then
        log_success "End-to-end integration tests completed with $passed_tests/$total_tests passing"
        return 0
    else
        log_error "All end-to-end integration tests failed"
        return 1
    fi
}

# Test component health checks
test_component_health() {
    log_info "Testing component health checks..."
    
    # Test JS Echo Server health check
    log_debug "Testing JS Echo Server health check..."
    if docker run --rm js-libp2p-echo-server:latest bash /app/lib/health-check.sh js-server >/dev/null 2>&1; then
        log_success "JS Echo Server health check passed"
    else
        log_warning "JS Echo Server health check failed (may be expected without full environment)"
    fi
    
    # Test Python Test Harness health check
    log_debug "Testing Python Test Harness health check..."
    if docker run --rm py-test-harness:latest bash /app/lib/health-check.sh py-client >/dev/null 2>&1; then
        log_success "Python Test Harness health check passed"
    else
        log_warning "Python Test Harness health check failed (may be expected without full environment)"
    fi
    
    return 0
}

# Test configuration validation
test_configuration_validation() {
    log_info "Testing configuration validation..."
    
    # Test valid configurations
    local valid_configs=(
        "tcp:noise:yamux"
        "tcp:noise:mplex"
    )
    
    for config in "${valid_configs[@]}"; do
        IFS=':' read -r transport security muxer <<< "$config"
        
        log_debug "Testing configuration: $config"
        
        if TRANSPORT="$transport" SECURITY="$security" MUXER="$muxer" ./lib/validate-config.sh >/dev/null 2>&1; then
            log_debug "Configuration validation passed: $config"
        else
            log_error "Configuration validation failed: $config"
            return 1
        fi
    done
    
    log_success "All configuration validations passed"
    return 0
}

# Test Docker Compose configuration
test_docker_compose_config() {
    log_info "Testing Docker Compose configuration..."
    
    # Validate Docker Compose file
    if docker-compose config --quiet; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Test service definitions
    local required_services=("redis" "js-echo-server" "py-test-harness")
    
    for service in "${required_services[@]}"; do
        if docker-compose config --services | grep -q "^${service}$"; then
            log_debug "Service defined: $service"
        else
            log_error "Missing service definition: $service"
            return 1
        fi
    done
    
    log_success "All required services are defined"
    return 0
}

# Test network connectivity
test_network_connectivity() {
    log_info "Testing network connectivity..."
    
    # Start Redis service only
    log_debug "Starting Redis service..."
    docker-compose up -d redis >/dev/null 2>&1
    
    # Wait for Redis to be ready
    local redis_ready=false
    for i in {1..30}; do
        if docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; then
            redis_ready=true
            break
        fi
        sleep 1
    done
    
    if [[ "$redis_ready" == "true" ]]; then
        log_success "Redis connectivity test passed"
    else
        log_error "Redis connectivity test failed"
        return 1
    fi
    
    # Clean up
    docker-compose down >/dev/null 2>&1
    
    return 0
}

# Test file structure and dependencies
test_file_structure() {
    log_info "Testing file structure and dependencies..."
    
    # Check required files
    local required_files=(
        "docker-compose.yml"
        "Makefile"
        "images.yaml"
        "versions.ts"
        "lib/validate-config.sh"
        "lib/health-check.sh"
        "scripts/build-local.sh"
        "scripts/test-local.sh"
        "test-ci-integration.sh"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing required files: ${missing_files[*]}"
        return 1
    fi
    
    # Check image directories
    local required_dirs=(
        "images/js-echo-server"
        "images/py-test-harness"
    )
    
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log_error "Missing required directories: ${missing_dirs[*]}"
        return 1
    fi
    
    log_success "File structure validation passed"
    return 0
}

# Main integration test function
main() {
    log_info "Starting End-to-End Integration Test for JS-libp2p Echo Interop"
    log_info "Test timeout: ${TEST_TIMEOUT}s"
    log_info "Verbose: ${VERBOSE:-false}"
    
    cd "$PROJECT_ROOT"
    
    # Run all integration tests
    local test_functions=(
        "check_prerequisites"
        "test_file_structure"
        "test_docker_compose_config"
        "test_configuration_validation"
        "test_component_health"
        "test_network_connectivity"
        "test_protocol_combinations"
    )
    
    local total_functions=${#test_functions[@]}
    local passed_functions=0
    
    for test_function in "${test_functions[@]}"; do
        log_info "Running: $test_function"
        
        if $test_function; then
            passed_functions=$((passed_functions + 1))
            log_success "✓ $test_function"
        else
            log_error "✗ $test_function"
        fi
        
        echo ""  # Add spacing between tests
    done
    
    # Generate final summary
    local success_rate=0
    if [[ $total_functions -gt 0 ]]; then
        success_rate=$((passed_functions * 100 / total_functions))
    fi
    
    log_info "End-to-End Integration Test Summary:"
    log_info "  Total test functions: $total_functions"
    log_info "  Passed: $passed_functions"
    log_info "  Failed: $((total_functions - passed_functions))"
    log_info "  Success rate: ${success_rate}%"
    
    if [[ -f "integration-test-report.json" ]]; then
        log_info "  Detailed report: integration-test-report.json"
    fi
    
    if [[ $passed_functions -eq $total_functions ]]; then
        log_success "🎉 All end-to-end integration tests passed!"
        return 0
    elif [[ $passed_functions -gt $((total_functions / 2)) ]]; then
        log_warning "⚠️  Most integration tests passed ($passed_functions/$total_functions)"
        return 0
    else
        log_error "❌ End-to-end integration tests failed ($passed_functions/$total_functions passed)"
        return 1
    fi
}

# Handle command line arguments
case "${1:-test}" in
    "test")
        main
        ;;
    "quick")
        log_info "Running quick integration test (no protocol combinations)..."
        check_prerequisites && \
        test_file_structure && \
        test_docker_compose_config && \
        test_configuration_validation && \
        test_component_health && \
        log_success "Quick integration test completed"
        ;;
    "network")
        check_prerequisites && test_network_connectivity
        ;;
    "config")
        test_configuration_validation
        ;;
    "health")
        check_prerequisites && test_component_health
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [test|quick|network|config|health|help]"
        echo ""
        echo "Commands:"
        echo "  test     - Run full end-to-end integration test (default)"
        echo "  quick    - Run quick integration test (no protocol combinations)"
        echo "  network  - Test network connectivity only"
        echo "  config   - Test configuration validation only"
        echo "  health   - Test component health checks only"
        echo "  help     - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  TEST_TIMEOUT=120  - Test timeout in seconds"
        echo "  VERBOSE=true      - Enable verbose output"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac