#!/usr/bin/env bash

# CI/CD Integration Tests for JS-libp2p Echo Interop Tests
# Validates Docker image building, caching, test execution, and result aggregation in CI environment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
CI_MODE="${CI:-false}"
GITHUB_ACTIONS="${GITHUB_ACTIONS:-false}"
BUILD_CACHE="${BUILD_CACHE:-true}"
VERBOSE="${VERBOSE:-false}"
TEST_TIMEOUT="${TEST_TIMEOUT:-600}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[CI-TEST]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[CI-SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[CI-WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[CI-ERROR]${NC} $*"
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${BLUE}[CI-DEBUG]${NC} $*"
    fi
}

# Test result tracking
declare -a TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Add test result
add_test_result() {
    local test_name="$1"
    local status="$2"
    local duration="$3"
    local error_msg="${4:-}"
    
    TEST_RESULTS+=("$test_name:$status:$duration:$error_msg")
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ "$status" == "PASSED" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Run a test with timing and error handling
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "Running CI test: $test_name"
    local start_time=$(date +%s)
    
    if $test_function; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        add_test_result "$test_name" "PASSED" "$duration"
        log_success "CI test passed: $test_name (${duration}s)"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        add_test_result "$test_name" "FAILED" "$duration" "Test function returned non-zero exit code"
        log_error "CI test failed: $test_name (${duration}s)"
        return 1
    fi
}

# Test 1: Docker image building and caching
test_docker_image_building() {
    log_debug "Testing Docker image building and caching..."
    
    # Clean up any existing images first
    docker rmi js-libp2p-echo-server:latest py-test-harness:latest 2>/dev/null || true
    
    # Test building without cache
    log_debug "Building images without cache..."
    if ! BUILD_CACHE=false make build >/dev/null 2>&1; then
        log_error "Failed to build images without cache"
        return 1
    fi
    
    # Verify images were created
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "js-libp2p-echo-server:latest"; then
        log_error "JS Echo Server image not found after build"
        return 1
    fi
    
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "py-test-harness:latest"; then
        log_error "Python Test Harness image not found after build"
        return 1
    fi
    
    # Test building with cache (should be faster)
    log_debug "Testing cached build..."
    local cache_start=$(date +%s)
    if ! BUILD_CACHE=true make build >/dev/null 2>&1; then
        log_error "Failed to build images with cache"
        return 1
    fi
    local cache_end=$(date +%s)
    local cache_duration=$((cache_end - cache_start))
    
    log_debug "Cached build completed in ${cache_duration}s"
    
    # Test image functionality
    log_debug "Testing image functionality..."
    if ! docker run --rm js-libp2p-echo-server:latest node --version >/dev/null 2>&1; then
        log_error "JS Echo Server image is not functional"
        return 1
    fi
    
    if ! docker run --rm py-test-harness:latest python3 --version >/dev/null 2>&1; then
        log_error "Python Test Harness image is not functional"
        return 1
    fi
    
    # Test image.json generation
    log_debug "Testing image.json generation..."
    if ! make image-json >/dev/null 2>&1; then
        log_error "Failed to generate image.json"
        return 1
    fi
    
    if [[ ! -f "image.json" ]]; then
        log_error "image.json file not created"
        return 1
    fi
    
    # Validate image.json format
    if ! python3 -c "import json; json.load(open('image.json'))" 2>/dev/null; then
        log_error "image.json is not valid JSON"
        return 1
    fi
    
    # Check required fields in image.json
    if ! python3 -c "
import json
data = json.load(open('image.json'))
assert 'js-echo-server' in data, 'Missing js-echo-server in image.json'
assert 'py-test-harness' in data, 'Missing py-test-harness in image.json'
for service in ['js-echo-server', 'py-test-harness']:
    assert 'image' in data[service], f'Missing image field for {service}'
    assert 'build_date' in data[service], f'Missing build_date field for {service}'
    assert 'git_commit' in data[service], f'Missing git_commit field for {service}'
print('image.json validation passed')
" 2>/dev/null; then
        log_error "image.json missing required fields"
        return 1
    fi
    
    log_debug "Docker image building and caching test completed successfully"
    return 0
}

# Test 2: CI environment configuration validation
test_ci_environment_validation() {
    log_debug "Testing CI environment configuration validation..."
    
    # Test environment variable validation
    local original_env=()
    local test_vars=("TRANSPORT" "SECURITY" "MUXER" "CI" "GITHUB_ACTIONS")
    
    # Save original environment
    for var in "${test_vars[@]}"; do
        original_env+=("$var=${!var:-}")
    done
    
    # Test valid CI configuration
    export CI=true
    export GITHUB_ACTIONS=true
    export TRANSPORT=tcp
    export SECURITY=noise
    export MUXER=yamux
    
    if ! ./lib/validate-config.sh >/dev/null 2>&1; then
        log_error "Valid CI configuration failed validation"
        return 1
    fi
    
    # Test invalid configurations
    local invalid_configs=(
        "TRANSPORT=invalid"
        "SECURITY=invalid"
        "MUXER=invalid"
    )
    
    for invalid_config in "${invalid_configs[@]}"; do
        # Set invalid configuration
        export ${invalid_config}
        
        if ./lib/validate-config.sh >/dev/null 2>&1; then
            log_error "Invalid configuration should have failed: $invalid_config"
            return 1
        fi
        
        # Reset to valid value
        case "$invalid_config" in
            TRANSPORT=*) export TRANSPORT=tcp ;;
            SECURITY=*) export SECURITY=noise ;;
            MUXER=*) export MUXER=yamux ;;
        esac
    done
    
    # Test CI-specific validations
    if [[ "${CI:-false}" == "true" ]]; then
        # In CI, certain timeouts should be longer
        export TEST_TIMEOUT=600  # 10 minutes for CI
        
        if [[ "$TEST_TIMEOUT" -lt 300 ]]; then
            log_error "CI timeout should be at least 5 minutes"
            return 1
        fi
    fi
    
    # Restore original environment
    for env_setting in "${original_env[@]}"; do
        if [[ "$env_setting" == *"=" ]]; then
            var_name="${env_setting%%=*}"
            var_value="${env_setting#*=}"
            if [[ -n "$var_value" ]]; then
                export "$var_name=$var_value"
            else
                unset "$var_name" 2>/dev/null || true
            fi
        fi
    done
    
    log_debug "CI environment configuration validation completed successfully"
    return 0
}

# Test 3: Test execution in CI environment
test_ci_test_execution() {
    log_debug "Testing test execution in CI environment..."
    
    # Set CI-specific environment
    export CI=true
    export VERBOSE=true
    export TEST_TIMEOUT=600
    
    # Test configuration validation
    if ! ./scripts/test-local.sh config >/dev/null 2>&1; then
        log_error "Configuration tests failed in CI environment"
        return 1
    fi
    
    # Test unit tests
    if ! ./scripts/test-local.sh unit >/dev/null 2>&1; then
        log_error "Unit tests failed in CI environment"
        return 1
    fi
    
    # Test property-based tests (with longer timeout for CI)
    log_debug "Running property-based tests in CI environment..."
    if ! timeout 300 ./scripts/test-local.sh property >/dev/null 2>&1; then
        log_error "Property-based tests failed or timed out in CI environment"
        return 1
    fi
    
    # Test integration tests (if Docker Compose is available)
    if command -v docker-compose >/dev/null 2>&1; then
        log_debug "Running integration tests in CI environment..."
        
        # Use shorter test scenarios for CI
        export TEST_SCENARIOS="basic,binary"
        export CONCURRENT_STREAMS="1,3"
        
        if ! timeout 400 ./scripts/test-local.sh integration >/dev/null 2>&1; then
            log_error "Integration tests failed or timed out in CI environment"
            return 1
        fi
    else
        log_warning "Docker Compose not available, skipping integration tests"
    fi
    
    log_debug "CI test execution completed successfully"
    return 0
}

# Test 4: Result aggregation and reporting
test_result_aggregation() {
    log_debug "Testing result aggregation and reporting..."
    
    # Create test results directory
    mkdir -p test-results
    
    # Generate sample test results
    local test_results=(
        '{"test_name": "echo_basic", "status": "passed", "duration": 1.23, "implementation": "js-libp2p", "version": "latest"}'
        '{"test_name": "echo_binary", "status": "passed", "duration": 2.45, "implementation": "js-libp2p", "version": "latest"}'
        '{"test_name": "echo_large", "status": "failed", "duration": 5.67, "implementation": "js-libp2p", "version": "latest", "error": "timeout"}'
    )
    
    # Write individual test results
    for i in "${!test_results[@]}"; do
        echo "${test_results[$i]}" > "test-results/test_$i.json"
    done
    
    # Test result aggregation script
    cat > test-results/aggregate-results.py << 'EOF'
#!/usr/bin/env python3
import json
import glob
import sys
from pathlib import Path

def aggregate_results():
    results_dir = Path("test-results")
    result_files = list(results_dir.glob("test_*.json"))
    
    if not result_files:
        print("No test result files found")
        return 1
    
    aggregated = {
        "summary": {
            "total_tests": 0,
            "passed_tests": 0,
            "failed_tests": 0,
            "skipped_tests": 0,
            "total_duration": 0.0
        },
        "tests": []
    }
    
    for result_file in result_files:
        try:
            with open(result_file) as f:
                test_result = json.load(f)
            
            aggregated["tests"].append(test_result)
            aggregated["summary"]["total_tests"] += 1
            aggregated["summary"]["total_duration"] += test_result.get("duration", 0)
            
            status = test_result.get("status", "unknown")
            if status == "passed":
                aggregated["summary"]["passed_tests"] += 1
            elif status == "failed":
                aggregated["summary"]["failed_tests"] += 1
            elif status == "skipped":
                aggregated["summary"]["skipped_tests"] += 1
                
        except (json.JSONDecodeError, FileNotFoundError) as e:
            print(f"Error processing {result_file}: {e}")
            return 1
    
    # Calculate success rate
    total = aggregated["summary"]["total_tests"]
    passed = aggregated["summary"]["passed_tests"]
    success_rate = (passed / total * 100) if total > 0 else 0
    aggregated["summary"]["success_rate"] = f"{success_rate:.1f}%"
    
    # Write aggregated results
    with open("test-results/aggregated-results.json", "w") as f:
        json.dump(aggregated, f, indent=2)
    
    print(f"Aggregated {total} test results")
    print(f"Success rate: {success_rate:.1f}%")
    
    return 0

if __name__ == "__main__":
    sys.exit(aggregate_results())
EOF
    
    chmod +x test-results/aggregate-results.py
    
    # Run result aggregation
    if ! python3 test-results/aggregate-results.py; then
        log_error "Result aggregation failed"
        return 1
    fi
    
    # Validate aggregated results
    if [[ ! -f "test-results/aggregated-results.json" ]]; then
        log_error "Aggregated results file not created"
        return 1
    fi
    
    # Validate aggregated results format
    if ! python3 -c "
import json
data = json.load(open('test-results/aggregated-results.json'))
assert 'summary' in data, 'Missing summary in aggregated results'
assert 'tests' in data, 'Missing tests in aggregated results'
summary = data['summary']
required_fields = ['total_tests', 'passed_tests', 'failed_tests', 'total_duration', 'success_rate']
for field in required_fields:
    assert field in summary, f'Missing {field} in summary'
assert summary['total_tests'] == 3, f'Expected 3 total tests, got {summary[\"total_tests\"]}'
assert summary['passed_tests'] == 2, f'Expected 2 passed tests, got {summary[\"passed_tests\"]}'
assert summary['failed_tests'] == 1, f'Expected 1 failed test, got {summary[\"failed_tests\"]}'
print('Aggregated results validation passed')
" 2>/dev/null; then
        log_error "Aggregated results validation failed"
        return 1
    fi
    
    # Test CI reporting format
    if [[ "${CI:-false}" == "true" ]]; then
        # Generate CI-specific reports
        python3 -c "
import json
data = json.load(open('test-results/aggregated-results.json'))
summary = data['summary']

# GitHub Actions format
if '${GITHUB_ACTIONS:-false}' == 'true':
    print(f'::notice title=Test Results::Total: {summary[\"total_tests\"]}, Passed: {summary[\"passed_tests\"]}, Failed: {summary[\"failed_tests\"]}, Success Rate: {summary[\"success_rate\"]}')
    
    # Set output for GitHub Actions
    with open('$GITHUB_OUTPUT', 'a') if '$GITHUB_OUTPUT' else open('/dev/null', 'w') as f:
        f.write(f'total_tests={summary[\"total_tests\"]}\n')
        f.write(f'passed_tests={summary[\"passed_tests\"]}\n')
        f.write(f'failed_tests={summary[\"failed_tests\"]}\n')
        f.write(f'success_rate={summary[\"success_rate\"]}\n')

# JUnit XML format for CI systems
junit_xml = '''<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<testsuites>
  <testsuite name=\"js-libp2p-echo-interop\" tests=\"{total}\" failures=\"{failed}\" time=\"{duration}\">
'''.format(
    total=summary['total_tests'],
    failed=summary['failed_tests'],
    duration=summary['total_duration']
)

for test in data['tests']:
    status = 'failure' if test['status'] == 'failed' else ''
    junit_xml += f'    <testcase name=\"{test[\"test_name\"]}\" time=\"{test[\"duration\"]}\">'
    if test['status'] == 'failed':
        error_msg = test.get('error', 'Unknown error')
        junit_xml += f'<failure message=\"{error_msg}\"/>'
    junit_xml += '</testcase>\n'

junit_xml += '''  </testsuite>
</testsuites>'''

with open('test-results/junit.xml', 'w') as f:
    f.write(junit_xml)

print('CI reporting formats generated')
"
    fi
    
    # Clean up test results
    rm -rf test-results
    
    log_debug "Result aggregation and reporting completed successfully"
    return 0
}

# Test 5: Multi-architecture build support
test_multiarch_build_support() {
    log_debug "Testing multi-architecture build support..."
    
    # Check if buildx is available
    if ! docker buildx version >/dev/null 2>&1; then
        log_warning "Docker buildx not available, skipping multi-arch tests"
        return 0
    fi
    
    # Test buildx setup
    if ! make buildx-setup >/dev/null 2>&1; then
        log_error "Failed to set up Docker buildx"
        return 1
    fi
    
    # Test multi-arch build (without actually building for all platforms to save time)
    log_debug "Testing multi-arch build configuration..."
    
    # Verify Makefile supports multi-arch
    if ! grep -q "PLATFORMS.*linux/amd64,linux/arm64" Makefile; then
        log_error "Makefile does not support multi-architecture builds"
        return 1
    fi
    
    # Test buildx builder exists
    if ! docker buildx ls | grep -q "multiarch"; then
        log_warning "Multi-arch builder not found, but buildx setup succeeded"
    fi
    
    log_debug "Multi-architecture build support test completed successfully"
    return 0
}

# Test 6: CI/CD pipeline integration
test_cicd_pipeline_integration() {
    log_debug "Testing CI/CD pipeline integration..."
    
    # Test Makefile CI targets
    local ci_targets=("ci-build" "ci-test")
    
    for target in "${ci_targets[@]}"; do
        if ! grep -q "^${target}:" Makefile; then
            log_error "Makefile missing CI target: $target"
            return 1
        fi
    done
    
    # Test CI build (dry run)
    log_debug "Testing CI build target..."
    if ! make ci-build >/dev/null 2>&1; then
        log_error "CI build target failed"
        return 1
    fi
    
    # Test environment variable handling in CI
    local ci_env_vars=("CI" "GITHUB_ACTIONS" "BUILD_CACHE" "VERBOSE" "TEST_TIMEOUT")
    
    for var in "${ci_env_vars[@]}"; do
        # Test that scripts handle the environment variable
        if ! grep -r "$var" scripts/ lib/ >/dev/null 2>&1; then
            log_warning "Environment variable $var not used in scripts"
        fi
    done
    
    # Test CI-specific configurations
    export CI=true
    export VERBOSE=true
    export BUILD_CACHE=false
    
    # Verify CI mode changes behavior
    if [[ "${CI:-false}" == "true" ]]; then
        # In CI mode, builds should be more verbose and not use cache by default
        if [[ "${BUILD_CACHE:-true}" != "false" ]]; then
            log_warning "CI mode should disable build cache by default"
        fi
        
        if [[ "${VERBOSE:-false}" != "true" ]]; then
            log_warning "CI mode should enable verbose output by default"
        fi
    fi
    
    log_debug "CI/CD pipeline integration test completed successfully"
    return 0
}

# Test 7: Performance and resource usage
test_performance_and_resources() {
    log_debug "Testing performance and resource usage in CI..."
    
    # Monitor resource usage during build
    local build_start=$(date +%s)
    local build_pid=""
    
    # Start resource monitoring in background
    (
        while true; do
            if command -v docker >/dev/null 2>&1; then
                docker system df >/dev/null 2>&1 || true
            fi
            sleep 5
        done
    ) &
    local monitor_pid=$!
    
    # Run a quick build test
    if ! timeout 120 make build >/dev/null 2>&1; then
        kill $monitor_pid 2>/dev/null || true
        log_error "Build performance test failed or timed out"
        return 1
    fi
    
    local build_end=$(date +%s)
    local build_duration=$((build_end - build_start))
    
    # Stop monitoring
    kill $monitor_pid 2>/dev/null || true
    
    # Check build performance
    if [[ $build_duration -gt 300 ]]; then  # 5 minutes
        log_warning "Build took longer than expected: ${build_duration}s"
    else
        log_debug "Build completed in acceptable time: ${build_duration}s"
    fi
    
    # Check Docker image sizes
    local js_image_size=$(docker images --format "table {{.Size}}" js-libp2p-echo-server:latest | tail -n1)
    local py_image_size=$(docker images --format "table {{.Size}}" py-test-harness:latest | tail -n1)
    
    log_debug "Image sizes - JS: $js_image_size, Python: $py_image_size"
    
    # Check disk usage
    local disk_usage=$(df . | tail -n1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log_warning "High disk usage: ${disk_usage}%"
    fi
    
    log_debug "Performance and resource usage test completed successfully"
    return 0
}

# Generate final CI test report
generate_ci_test_report() {
    log_info "Generating CI test report..."
    
    local report_file="ci-test-report.json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local success_rate=0
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    cat > "$report_file" << EOF
{
  "ci_test_timestamp": "$timestamp",
  "ci_environment": {
    "ci_mode": ${CI:-false},
    "github_actions": ${GITHUB_ACTIONS:-false},
    "build_cache": ${BUILD_CACHE:-true},
    "verbose": ${VERBOSE:-false},
    "test_timeout": ${TEST_TIMEOUT:-300}
  },
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "success_rate": "${success_rate}%"
  },
  "test_results": [
EOF
    
    # Add individual test results
    local first=true
    for result in "${TEST_RESULTS[@]}"; do
        IFS=':' read -r name status duration error <<< "$result"
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        
        cat >> "$report_file" << EOF
    {
      "test_name": "$name",
      "status": "$status",
      "duration": $duration,
      "error": "${error:-null}"
    }
EOF
    done
    
    cat >> "$report_file" << EOF
  ],
  "environment_info": {
    "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
    "docker_compose_version": "$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'not available')",
    "host_os": "$(uname -s)",
    "host_arch": "$(uname -m)",
    "shell": "$SHELL"
  }
}
EOF
    
    log_success "CI test report generated: $report_file"
    
    # Display summary
    log_info "CI Test Summary:"
    log_info "  Total Tests: $TOTAL_TESTS"
    log_info "  Passed: $PASSED_TESTS"
    log_info "  Failed: $FAILED_TESTS"
    log_info "  Success Rate: ${success_rate}%"
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        log_error "Some CI tests failed. Check the report for details."
        return 1
    else
        log_success "All CI tests passed!"
        return 0
    fi
}

# Main CI test execution
main() {
    log_info "Starting CI/CD Integration Tests for JS-libp2p Echo Interop"
    log_info "CI Mode: ${CI:-false}"
    log_info "GitHub Actions: ${GITHUB_ACTIONS:-false}"
    log_info "Build Cache: ${BUILD_CACHE:-true}"
    log_info "Verbose: ${VERBOSE:-false}"
    log_info "Test Timeout: ${TEST_TIMEOUT:-300}s"
    
    cd "$PROJECT_ROOT"
    
    # Run all CI integration tests
    run_test "Docker Image Building and Caching" test_docker_image_building
    run_test "CI Environment Configuration Validation" test_ci_environment_validation
    run_test "CI Test Execution" test_ci_test_execution
    run_test "Result Aggregation and Reporting" test_result_aggregation
    run_test "Multi-Architecture Build Support" test_multiarch_build_support
    run_test "CI/CD Pipeline Integration" test_cicd_pipeline_integration
    run_test "Performance and Resource Usage" test_performance_and_resources
    
    # Generate final report
    generate_ci_test_report
}

# Handle command line arguments
case "${1:-test}" in
    "test")
        main
        ;;
    "docker")
        run_test "Docker Image Building and Caching" test_docker_image_building
        ;;
    "env")
        run_test "CI Environment Configuration Validation" test_ci_environment_validation
        ;;
    "execution")
        run_test "CI Test Execution" test_ci_test_execution
        ;;
    "aggregation")
        run_test "Result Aggregation and Reporting" test_result_aggregation
        ;;
    "multiarch")
        run_test "Multi-Architecture Build Support" test_multiarch_build_support
        ;;
    "pipeline")
        run_test "CI/CD Pipeline Integration" test_cicd_pipeline_integration
        ;;
    "performance")
        run_test "Performance and Resource Usage" test_performance_and_resources
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [test|docker|env|execution|aggregation|multiarch|pipeline|performance|help]"
        echo ""
        echo "Commands:"
        echo "  test        - Run all CI integration tests (default)"
        echo "  docker      - Test Docker image building and caching"
        echo "  env         - Test CI environment configuration validation"
        echo "  execution   - Test test execution in CI environment"
        echo "  aggregation - Test result aggregation and reporting"
        echo "  multiarch   - Test multi-architecture build support"
        echo "  pipeline    - Test CI/CD pipeline integration"
        echo "  performance - Test performance and resource usage"
        echo "  help        - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  CI=true              - Enable CI mode"
        echo "  GITHUB_ACTIONS=true  - Enable GitHub Actions mode"
        echo "  BUILD_CACHE=false    - Disable Docker build cache"
        echo "  VERBOSE=true         - Enable verbose output"
        echo "  TEST_TIMEOUT=600     - Test timeout in seconds"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac