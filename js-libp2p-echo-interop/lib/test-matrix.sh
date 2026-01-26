#!/usr/bin/env bash

# Test Matrix Generation Logic for JS-libp2p Echo Interop Tests
# Generates test combinations from implementation capabilities
# Supports transport/security/muxer parameter combinations with environment variable configuration mapping

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MATRIX_OUTPUT_DIR="${PROJECT_ROOT}/test-matrix"
VERSIONS_FILE="${PROJECT_ROOT}/versions.ts"

# Default implementation capabilities
IMPLEMENTATIONS="js-libp2p:server py-libp2p:client"
TRANSPORTS="tcp"
SECURITY_PROTOCOLS="noise"
MUXERS="yamux mplex"
TEST_SCENARIOS="basic:Basic_text_echo_test binary:Binary_payload_echo_test large:Large_payload_1MB_echo_test concurrent:Concurrent_streams_echo_test"

# Helper functions to work with key-value pairs
get_implementation_role() {
    local impl="$1"
    case "$impl" in
        "js-libp2p") echo "server" ;;
        "py-libp2p") echo "client" ;;
        *) echo "unknown" ;;
    esac
}

get_scenario_description() {
    local scenario="$1"
    case "$scenario" in
        "basic") echo "Basic text echo test" ;;
        "binary") echo "Binary payload echo test" ;;
        "large") echo "Large payload (1MB) echo test" ;;
        "concurrent") echo "Concurrent streams echo test" ;;
        *) echo "Unknown test scenario" ;;
    esac
}

# Logging functions
log_info() {
    echo "[MATRIX-INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_error() {
    echo "[MATRIX-ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[MATRIX-DEBUG] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
    fi
}

# Load implementation capabilities from versions.ts
load_implementation_capabilities() {
    local versions_file="$1"
    
    if [[ ! -f "$versions_file" ]]; then
        log_error "Versions file not found: $versions_file"
        return 1
    fi
    
    log_info "Loading implementation capabilities from $versions_file"
    
    # Check if we have node/ts-node available to parse TypeScript
    if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
        log_debug "Node.js available, attempting to parse TypeScript"
        
        # Create a temporary JavaScript file to extract implementation data
        local temp_js
        temp_js=$(mktemp -t versions_parser.XXXXXX.js)
        
        cat > "$temp_js" << 'EOF'
// Simple TypeScript-to-JavaScript converter for versions.ts parsing
const fs = require('fs');
const path = require('path');

const versionsFile = process.argv[2];
const versionsContent = fs.readFileSync(versionsFile, 'utf8');

// Extract implementation data using regex (simplified approach)
// In a real implementation, you'd use a proper TypeScript parser

// Extract py-libp2p implementation
const pyLibp2pMatch = versionsContent.match(/pyLibp2pImplementation[^}]+transports:\s*\[([^\]]+)\][^}]+secureChannels:\s*\[([^\]]+)\][^}]+muxers:\s*\[([^\]]+)\]/s);

// Extract js-libp2p implementation  
const jsLibp2pMatch = versionsContent.match(/jsLibp2pEchoServerImplementation[^}]+transports:\s*\[([^\]]+)\][^}]+secureChannels:\s*\[([^\]]+)\][^}]+muxers:\s*\[([^\]]+)\]/s);

const result = {
    implementations: {},
    transports: [],
    secureChannels: [],
    muxers: []
};

if (pyLibp2pMatch) {
    const transports = pyLibp2pMatch[1].match(/'([^']+)'/g) || [];
    const secureChannels = pyLibp2pMatch[2].match(/'([^']+)'/g) || [];
    const muxers = pyLibp2pMatch[3].match(/'([^']+)'/g) || [];
    
    result.implementations['py-libp2p'] = {
        role: 'client',
        transports: transports.map(t => t.replace(/'/g, '')),
        secureChannels: secureChannels.map(s => s.replace(/'/g, '')),
        muxers: muxers.map(m => m.replace(/'/g, ''))
    };
    
    // Add to global lists
    transports.forEach(t => {
        const transport = t.replace(/'/g, '');
        if (!result.transports.includes(transport)) {
            result.transports.push(transport);
        }
    });
    
    secureChannels.forEach(s => {
        const secure = s.replace(/'/g, '');
        if (!result.secureChannels.includes(secure)) {
            result.secureChannels.push(secure);
        }
    });
    
    muxers.forEach(m => {
        const muxer = m.replace(/'/g, '');
        if (!result.muxers.includes(muxer)) {
            result.muxers.push(muxer);
        }
    });
}

if (jsLibp2pMatch) {
    const transports = jsLibp2pMatch[1].match(/'([^']+)'/g) || [];
    const secureChannels = jsLibp2pMatch[2].match(/'([^']+)'/g) || [];
    const muxers = jsLibp2pMatch[3].match(/'([^']+)'/g) || [];
    
    result.implementations['js-libp2p'] = {
        role: 'server',
        transports: transports.map(t => t.replace(/'/g, '')),
        secureChannels: secureChannels.map(s => s.replace(/'/g, '')),
        muxers: muxers.map(m => m.replace(/'/g, ''))
    };
}

console.log(JSON.stringify(result, null, 2));
EOF
        
        # Parse versions.ts and extract capabilities
        local capabilities_json
        if capabilities_json=$(node "$temp_js" "$versions_file" 2>/dev/null); then
            log_debug "Successfully parsed versions.ts"
            
            # Extract capabilities from JSON
            local parsed_transports
            parsed_transports=$(echo "$capabilities_json" | jq -r '.transports[]' 2>/dev/null | tr '\n' ' ')
            
            local parsed_security
            parsed_security=$(echo "$capabilities_json" | jq -r '.secureChannels[]' 2>/dev/null | tr '\n' ' ')
            
            local parsed_muxers
            parsed_muxers=$(echo "$capabilities_json" | jq -r '.muxers[]' 2>/dev/null | tr '\n' ' ')
            
            # Update global variables if parsing was successful
            if [[ -n "$parsed_transports" ]]; then
                TRANSPORTS="$parsed_transports"
                log_debug "Updated transports from versions.ts: $TRANSPORTS"
            fi
            
            if [[ -n "$parsed_security" ]]; then
                SECURITY_PROTOCOLS="$parsed_security"
                log_debug "Updated security protocols from versions.ts: $SECURITY_PROTOCOLS"
            fi
            
            if [[ -n "$parsed_muxers" ]]; then
                MUXERS="$parsed_muxers"
                log_debug "Updated muxers from versions.ts: $MUXERS"
            fi
            
            log_info "Successfully loaded capabilities from versions.ts"
        else
            log_error "Failed to parse versions.ts, using defaults"
        fi
        
        # Cleanup
        rm -f "$temp_js"
    else
        log_debug "Node.js not available, using default capabilities"
    fi
    
    log_info "Final capabilities - Implementations: $IMPLEMENTATIONS, Transports: $TRANSPORTS, Security: $SECURITY_PROTOCOLS, Muxers: $MUXERS"
}

# Generate test matrix combinations
generate_test_matrix() {
    local output_dir="$1"
    
    log_info "Generating test matrix combinations"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    local matrix_file="$output_dir/test-matrix.json"
    local combinations_count=0
    
    # Start JSON output
    cat > "$matrix_file" << 'EOF'
{
  "metadata": {
    "generated_at": "",
    "generator": "js-libp2p-echo-interop/lib/test-matrix.sh",
    "version": "1.0.0"
  },
  "implementations": {},
  "test_combinations": []
}
EOF
    
    # Update metadata
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Use a temporary file for JSON manipulation
    local temp_file
    temp_file=$(mktemp)
    
    # Update metadata and implementations
    jq --arg timestamp "$timestamp" \
       --arg implementations "$IMPLEMENTATIONS" \
       '.metadata.generated_at = $timestamp | .implementations = ($implementations | split(" ") | map(split(":") | {key: .[0], value: {role: .[1]}}) | from_entries)' \
       "$matrix_file" > "$temp_file" && mv "$temp_file" "$matrix_file"
    
    # Generate all combinations
    for transport in $TRANSPORTS; do
        for security in $SECURITY_PROTOCOLS; do
            for muxer in $MUXERS; do
                for scenario_pair in $TEST_SCENARIOS; do
                    local scenario
                    scenario=$(echo "$scenario_pair" | cut -d: -f1)
                    local scenario_desc
                    scenario_desc=$(get_scenario_description "$scenario")
                    
                    # Create test combination
                    local combination_id="${transport}-${security}-${muxer}-${scenario}"
                    local combination_name="Echo Interop: ${transport}/${security}/${muxer} - ${scenario}"
                    
                    # Generate environment variables
                    local env_vars="{
                        \"TRANSPORT\": \"$transport\",
                        \"SECURITY\": \"$security\",
                        \"MUXER\": \"$muxer\",
                        \"TEST_SCENARIO\": \"$scenario\",
                        \"TEST_NAME\": \"$combination_id\",
                        \"JS_VERSION\": \"latest\",
                        \"PY_VERSION\": \"v0.5.0\"
                    }"
                    
                    # Create combination object
                    local combination="{
                        \"id\": \"$combination_id\",
                        \"name\": \"$combination_name\",
                        \"description\": \"$scenario_desc\",
                        \"transport\": \"$transport\",
                        \"security\": \"$security\",
                        \"muxer\": \"$muxer\",
                        \"scenario\": \"$scenario\",
                        \"environment\": $env_vars,
                        \"implementations\": {
                            \"server\": \"js-libp2p\",
                            \"client\": \"py-libp2p\"
                        },
                        \"timeout\": 60,
                        \"retries\": 3,
                        \"tags\": [\"interop\", \"echo\", \"$transport\", \"$security\", \"$muxer\", \"$scenario\"]
                    }"
                    
                    # Add combination to matrix
                    jq --argjson combination "$combination" \
                       '.test_combinations += [$combination]' \
                       "$matrix_file" > "$temp_file" && mv "$temp_file" "$matrix_file"
                    
                    combinations_count=$((combinations_count + 1))
                    
                    log_debug "Generated combination: $combination_id"
                done
            done
        done
    done
    
    log_info "Generated $combinations_count test combinations in $matrix_file"
    
    # Generate additional output formats
    generate_docker_compose_matrix "$output_dir"
    generate_makefile_targets "$output_dir"
    generate_test_scripts "$output_dir"
    
    return 0
}

# Generate Docker Compose matrix files
generate_docker_compose_matrix() {
    local output_dir="$1"
    local compose_dir="$output_dir/compose"
    
    log_info "Generating Docker Compose matrix files"
    
    mkdir -p "$compose_dir"
    
    # Read test combinations from matrix file
    local matrix_file="$output_dir/test-matrix.json"
    
    # Generate individual compose files for each combination
    jq -r '.test_combinations[] | @base64' "$matrix_file" | while read -r combination_b64; do
        local combination
        combination=$(echo "$combination_b64" | base64 -d)
        
        local test_id
        test_id=$(echo "$combination" | jq -r '.id')
        
        local compose_file="$compose_dir/docker-compose.${test_id}.yml"
        
        # Generate compose file content
        cat > "$compose_file" << EOF
# Docker Compose configuration for test: $test_id
# Generated automatically by test matrix generator

version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: echo-redis-${test_id}
    networks:
      - echo-network-${test_id}
    command: redis-server --appendonly no --save ""
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  js-echo-server:
    build:
      context: ../images/js-echo-server
      dockerfile: Dockerfile
    container_name: echo-server-${test_id}
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - echo-network-${test_id}
    environment:
EOF
        
        # Add environment variables from combination
        echo "$combination" | jq -r '.environment | to_entries[] | "      \(.key): \"\(.value)\""' >> "$compose_file"
        
        cat >> "$compose_file" << EOF
      REDIS_ADDR: "redis:6379"
      IS_DIALER: "false"

  py-test-harness:
    build:
      context: ../images/py-test-harness
      dockerfile: Dockerfile
    container_name: echo-client-${test_id}
    depends_on:
      redis:
        condition: service_healthy
      js-echo-server:
        condition: service_started
    networks:
      - echo-network-${test_id}
    environment:
EOF
        
        # Add environment variables from combination
        echo "$combination" | jq -r '.environment | to_entries[] | "      \(.key): \"\(.value)\""' >> "$compose_file"
        
        cat >> "$compose_file" << EOF
      REDIS_ADDR: "redis:6379"
      IS_DIALER: "true"
    volumes:
      - test-results-${test_id}:/app/results

networks:
  echo-network-${test_id}:
    driver: bridge

volumes:
  test-results-${test_id}:
    driver: local
EOF
        
        log_debug "Generated compose file: $compose_file"
    done
    
    log_info "Generated Docker Compose matrix files in $compose_dir"
}

# Generate Makefile targets for test matrix
generate_makefile_targets() {
    local output_dir="$1"
    local makefile="$output_dir/Makefile.matrix"
    
    log_info "Generating Makefile targets for test matrix"
    
    cat > "$makefile" << 'EOF'
# Makefile for JS-libp2p Echo Interop Test Matrix
# Generated automatically by test matrix generator

.PHONY: help test-all test-clean test-list

help:
	@echo "JS-libp2p Echo Interop Test Matrix"
	@echo ""
	@echo "Available targets:"
	@echo "  test-all     - Run all test combinations"
	@echo "  test-clean   - Clean up test artifacts"
	@echo "  test-list    - List all test combinations"
	@echo "  test-<id>    - Run specific test combination"
	@echo ""

test-all: $(TEST_TARGETS)

test-clean:
	@echo "Cleaning up test artifacts..."
	@docker-compose -f ../docker-compose.yml down --remove-orphans --volumes 2>/dev/null || true
	@find compose -name "docker-compose.*.yml" -exec docker-compose -f {} down --remove-orphans --volumes \; 2>/dev/null || true
	@docker system prune -f --volumes

test-list:
	@echo "Available test combinations:"
	@jq -r '.test_combinations[] | "  \(.id) - \(.name)"' test-matrix.json

EOF
    
    # Add individual test targets
    local matrix_file="$output_dir/test-matrix.json"
    
    echo "# Individual test targets" >> "$makefile"
    echo "TEST_TARGETS := \\" >> "$makefile"
    
    jq -r '.test_combinations[] | .id' "$matrix_file" | while read -r test_id; do
        echo "	test-$test_id \\" >> "$makefile"
    done
    
    echo "" >> "$makefile"
    
    # Generate test target rules
    jq -r '.test_combinations[] | @base64' "$matrix_file" | while read -r combination_b64; do
        local combination
        combination=$(echo "$combination_b64" | base64 -d)
        
        local test_id
        test_id=$(echo "$combination" | jq -r '.id')
        
        local test_name
        test_name=$(echo "$combination" | jq -r '.name')
        
        cat >> "$makefile" << EOF
test-$test_id:
	@echo "Running test: $test_name"
	@docker-compose -f compose/docker-compose.$test_id.yml up --build --abort-on-container-exit
	@docker-compose -f compose/docker-compose.$test_id.yml down --remove-orphans --volumes

EOF
    done
    
    log_info "Generated Makefile targets in $makefile"
}

# Generate test execution scripts
generate_test_scripts() {
    local output_dir="$1"
    local scripts_dir="$output_dir/scripts"
    
    log_info "Generating test execution scripts"
    
    mkdir -p "$scripts_dir"
    
    # Generate main test runner script
    local runner_script="$scripts_dir/run-test-matrix.sh"
    
    cat > "$runner_script" << 'EOF'
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
EOF
    
    chmod +x "$runner_script"
    
    log_info "Generated test execution scripts in $scripts_dir"
}

# Validate test matrix
validate_test_matrix() {
    local matrix_file="$1"
    
    log_info "Validating test matrix: $matrix_file"
    
    if [[ ! -f "$matrix_file" ]]; then
        log_error "Matrix file not found: $matrix_file"
        return 1
    fi
    
    # Validate JSON structure
    if ! jq empty "$matrix_file" 2>/dev/null; then
        log_error "Invalid JSON in matrix file"
        return 1
    fi
    
    # Validate required fields
    local required_fields=("metadata" "implementations" "test_combinations")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$matrix_file" >/dev/null; then
            log_error "Missing required field: $field"
            return 1
        fi
    done
    
    # Validate test combinations
    local combinations_count
    combinations_count=$(jq '.test_combinations | length' "$matrix_file")
    
    if [[ $combinations_count -eq 0 ]]; then
        log_error "No test combinations found"
        return 1
    fi
    
    log_info "Matrix validation passed: $combinations_count combinations"
    return 0
}

# Main execution
main() {
    local command="${1:-generate}"
    
    case "$command" in
        "generate")
            log_info "Generating test matrix"
            
            # Load implementation capabilities
            if [[ -f "$VERSIONS_FILE" ]]; then
                load_implementation_capabilities "$VERSIONS_FILE"
            else
                log_info "Versions file not found, using default capabilities"
            fi
            
            # Generate test matrix
            generate_test_matrix "$MATRIX_OUTPUT_DIR"
            
            # Validate generated matrix
            validate_test_matrix "$MATRIX_OUTPUT_DIR/test-matrix.json"
            
            log_info "Test matrix generation completed"
            ;;
        
        "validate")
            local matrix_file="${2:-$MATRIX_OUTPUT_DIR/test-matrix.json}"
            validate_test_matrix "$matrix_file"
            ;;
        
        "list")
            local matrix_file="${2:-$MATRIX_OUTPUT_DIR/test-matrix.json}"
            if [[ -f "$matrix_file" ]]; then
                jq -r '.test_combinations[] | "\(.id) - \(.name)"' "$matrix_file"
            else
                log_error "Matrix file not found: $matrix_file"
                return 1
            fi
            ;;
        
        "help"|*)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  generate    - Generate test matrix (default)"
            echo "  validate    - Validate existing test matrix"
            echo "  list        - List test combinations"
            echo "  help        - Show this help"
            echo ""
            echo "Environment variables:"
            echo "  DEBUG       - Enable debug logging (true/false)"
            echo ""
            ;;
    esac
}

# Check for required dependencies
check_dependencies() {
    local deps=("jq" "docker" "docker-compose")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "Required dependency not found: $dep"
            return 1
        fi
    done
    
    return 0
}

# Initialize
if ! check_dependencies; then
    log_error "Missing required dependencies"
    exit 1
fi

# Execute main function
main "$@"