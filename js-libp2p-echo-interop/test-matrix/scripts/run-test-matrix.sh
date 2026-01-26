#!/usr/bin/env bash

# Test Matrix Runner for JS-libp2p Echo Interop Tests
# Generated automatically by test matrix generator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATRIX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$MATRIX_DIR/.." && pwd)"

# Configuration
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"
TIMEOUT="${TIMEOUT:-300}"
RESULTS_DIR="${RESULTS_DIR:-$MATRIX_DIR/results}"

# Logging functions
log_info() {
    echo "[RUNNER-INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_error() {
    echo "[RUNNER-ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

# Load test matrix
load_test_matrix() {
    local matrix_file="$MATRIX_DIR/test-matrix.json"
    
    if [[ ! -f "$matrix_file" ]]; then
        log_error "Test matrix file not found: $matrix_file"
        return 1
    fi
    
    jq -r '.test_combinations[] | .id' "$matrix_file"
}

# Run single test
run_single_test() {
    local test_id="$1"
    local compose_file="$MATRIX_DIR/compose/docker-compose.$test_id.yml"
    local result_file="$RESULTS_DIR/$test_id.json"
    
    log_info "Running test: $test_id"
    
    mkdir -p "$RESULTS_DIR"
    
    local start_time
    start_time=$(date +%s)
    
    local exit_code=0
    
    # Run test with timeout
    if timeout "$TIMEOUT" docker-compose -f "$compose_file" up --build --abort-on-container-exit; then
        log_info "Test $test_id completed successfully"
    else
        exit_code=$?
        log_error "Test $test_id failed with exit code $exit_code"
    fi
    
    # Cleanup
    docker-compose -f "$compose_file" down --remove-orphans --volumes >/dev/null 2>&1 || true
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Generate result
    cat > "$result_file" << RESULT_EOF
{
    "test_id": "$test_id",
    "status": "$([ $exit_code -eq 0 ] && echo "passed" || echo "failed")",
    "exit_code": $exit_code,
    "duration": $duration,
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
RESULT_EOF
    
    return $exit_code
}

# Main execution
main() {
    local test_filter="${1:-}"
    
    log_info "Starting test matrix execution"
    
    # Load test combinations
    local test_ids
    if [[ -n "$test_filter" ]]; then
        test_ids="$test_filter"
    else
        test_ids=$(load_test_matrix)
    fi
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # Run tests
    for test_id in $test_ids; do
        total_tests=$((total_tests + 1))
        
        if run_single_test "$test_id"; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    # Generate summary
    log_info "Test matrix execution completed"
    log_info "Total tests: $total_tests"
    log_info "Passed: $passed_tests"
    log_info "Failed: $failed_tests"
    
    # Generate summary report
    local summary_file="$RESULTS_DIR/summary.json"
    cat > "$summary_file" << SUMMARY_EOF
{
    "total": $total_tests,
    "passed": $passed_tests,
    "failed": $failed_tests,
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
SUMMARY_EOF
    
    return $([[ $failed_tests -eq 0 ]] && echo 0 || echo 1)
}

# Execute main function
main "$@"
