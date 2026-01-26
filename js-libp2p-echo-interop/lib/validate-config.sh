#!/usr/bin/env bash

# Configuration Validation Script for JS-libp2p Echo Interop Tests
# Validates environment variable combinations and provides clear error messages
# for invalid configurations with debugging and diagnostic output.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging functions
log_info() {
    echo "[CONFIG-INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_error() {
    echo "[CONFIG-ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[CONFIG-DEBUG] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
    fi
}

# Supported protocol options
SUPPORTED_TRANSPORTS="tcp quic websocket"
SUPPORTED_SECURITY="noise tls"
SUPPORTED_MUXERS="yamux mplex"

# Validation functions
validate_protocol_value() {
    local protocol_type="$1"
    local value="$2"
    local supported=""
    
    case "$protocol_type" in
        "transports") supported="$SUPPORTED_TRANSPORTS" ;;
        "security") supported="$SUPPORTED_SECURITY" ;;
        "muxers") supported="$SUPPORTED_MUXERS" ;;
        *) 
            log_error "Unknown protocol type: $protocol_type"
            return 1
            ;;
    esac
    
    if [[ " $supported " != *" $value "* ]]; then
        log_error "Unsupported $protocol_type: $value. Supported: $supported"
        return 1
    fi
    
    return 0
}

validate_boolean() {
    local name="$1"
    local value="$2"
    
    if [[ "$value" != "true" && "$value" != "false" ]]; then
        log_error "$name must be 'true' or 'false', got: $value"
        return 1
    fi
    
    return 0
}

validate_integer() {
    local name="$1"
    local value="$2"
    local min="${3:-0}"
    local max="${4:-2147483647}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "$name must be an integer, got: $value"
        return 1
    fi
    
    if [[ $value -lt $min || $value -gt $max ]]; then
        log_error "$name out of range: $value. Must be $min-$max"
        return 1
    fi
    
    return 0
}

validate_float() {
    local name="$1"
    local value="$2"
    local min="${3:-0}"
    local max="${4:-1000000}"
    
    if ! [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        log_error "$name must be a number, got: $value"
        return 1
    fi
    
    # Use bc for floating point comparison if available
    if command -v bc >/dev/null 2>&1; then
        if [[ $(echo "$value < $min" | bc -l) -eq 1 ]] || [[ $(echo "$value > $max" | bc -l) -eq 1 ]]; then
            log_error "$name out of range: $value. Must be $min-$max"
            return 1
        fi
    else
        # Fallback to integer comparison (less precise)
        local int_value=${value%.*}
        local int_min=${min%.*}
        local int_max=${max%.*}
        
        if [[ $int_value -lt $int_min || $int_value -gt $int_max ]]; then
            log_error "$name out of range: $value. Must be approximately $min-$max"
            return 1
        fi
    fi
    
    return 0
}

validate_redis_address() {
    local redis_addr="$1"
    
    if [[ -z "$redis_addr" ]]; then
        log_error "Redis address cannot be empty"
        return 1
    fi
    
    # Check if it's a URL format
    if [[ "$redis_addr" =~ ^redis:// ]]; then
        # Extract host and port from URL
        local url_pattern="^redis://([^:]+):([0-9]+)/?$"
        if [[ "$redis_addr" =~ $url_pattern ]]; then
            local host="${BASH_REMATCH[1]}"
            local port="${BASH_REMATCH[2]}"
            
            if [[ -z "$host" ]]; then
                log_error "Redis host cannot be empty in URL: $redis_addr"
                return 1
            fi
            
            if ! validate_integer "Redis port" "$port" 1 65535; then
                return 1
            fi
        else
            log_error "Invalid Redis URL format: $redis_addr. Expected: redis://host:port"
            return 1
        fi
    else
        # Assume host:port format
        if [[ "$redis_addr" != *":"* ]]; then
            log_error "Redis address should include port (host:port), got: $redis_addr"
            return 1
        fi
        
        local host="${redis_addr%:*}"
        local port="${redis_addr##*:}"
        
        if [[ -z "$host" ]]; then
            log_error "Redis host cannot be empty"
            return 1
        fi
        
        if ! validate_integer "Redis port" "$port" 1 65535; then
            return 1
        fi
    fi
    
    return 0
}

validate_host_address() {
    local host="$1"
    
    if [[ -z "$host" ]]; then
        log_error "Host address cannot be empty"
        return 1
    fi
    
    # Basic validation for common host formats
    local ipv4_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    local hostname_pattern="^[a-zA-Z0-9.-]+$"
    
    if [[ "$host" =~ $ipv4_pattern ]]; then
        # Validate IPv4 octets
        IFS='.' read -ra octets <<< "$host"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                log_error "Invalid IPv4 address: $host (octet $octet > 255)"
                return 1
            fi
        done
    elif [[ "$host" =~ $hostname_pattern ]]; then
        # Valid hostname format
        :
    else
        log_error "Invalid host format: $host"
        return 1
    fi
    
    return 0
}

check_protocol_compatibility() {
    local transport="$1"
    local security="$2"
    local muxer="$3"
    local is_dialer="$4"
    
    local has_warnings=false
    local has_errors=false
    
    # Transport-specific checks
    case "$transport" in
        "quic")
            if [[ "$security" == "tls" ]]; then
                log_info "WARNING: QUIC already includes TLS 1.3, additional TLS layer is redundant"
                has_warnings=true
            fi
            ;;
        "websocket")
            if [[ "$is_dialer" == "false" ]]; then
                log_error "WebSocket transport only supports dialer role in current implementation"
                has_errors=true
            fi
            ;;
    esac
    
    # Muxer-specific checks
    if [[ "$muxer" == "mplex" ]]; then
        log_info "WARNING: Mplex is deprecated, consider using Yamux for better performance"
        has_warnings=true
    fi
    
    # Return success if no errors (warnings are okay)
    [[ "$has_errors" == "false" ]]
}

validate_environment_config() {
    local errors=0
    
    log_info "Validating environment configuration..."
    
    # Get configuration values with defaults
    local transport="${TRANSPORT:-tcp}"
    local security="${SECURITY:-noise}"
    local muxer="${MUXER:-yamux}"
    local is_dialer="${IS_DIALER:-true}"
    local host="${HOST:-0.0.0.0}"
    local port="${PORT:-0}"
    local redis_addr="${REDIS_ADDR:-redis:6379}"
    local redis_timeout="${REDIS_TIMEOUT:-30}"
    local connection_timeout="${CONNECTION_TIMEOUT:-10}"
    local test_timeout="${TEST_TIMEOUT:-30}"
    local max_retries="${MAX_RETRIES:-3}"
    local retry_delay="${RETRY_DELAY:-1.0}"
    local log_level="${LOG_LEVEL:-INFO}"
    
    log_debug "Configuration values:"
    log_debug "  TRANSPORT=$transport"
    log_debug "  SECURITY=$security"
    log_debug "  MUXER=$muxer"
    log_debug "  IS_DIALER=$is_dialer"
    log_debug "  HOST=$host"
    log_debug "  PORT=$port"
    log_debug "  REDIS_ADDR=$redis_addr"
    log_debug "  REDIS_TIMEOUT=$redis_timeout"
    log_debug "  CONNECTION_TIMEOUT=$connection_timeout"
    log_debug "  TEST_TIMEOUT=$test_timeout"
    log_debug "  MAX_RETRIES=$max_retries"
    log_debug "  RETRY_DELAY=$retry_delay"
    log_debug "  LOG_LEVEL=$log_level"
    
    # Protocol validation
    if ! validate_protocol_value "transports" "$transport"; then
        ((errors++))
    fi
    
    if ! validate_protocol_value "security" "$security"; then
        ((errors++))
    fi
    
    if ! validate_protocol_value "muxers" "$muxer"; then
        ((errors++))
    fi
    
    # Boolean validation
    if ! validate_boolean "IS_DIALER" "$is_dialer"; then
        ((errors++))
    fi
    
    # Network configuration validation
    if ! validate_host_address "$host"; then
        ((errors++))
    fi
    
    if ! validate_integer "PORT" "$port" 0 65535; then
        ((errors++))
    fi
    
    # Redis configuration validation
    if ! validate_redis_address "$redis_addr"; then
        ((errors++))
    fi
    
    # Timeout validation
    if ! validate_integer "REDIS_TIMEOUT" "$redis_timeout" 1 600; then
        ((errors++))
    fi
    
    if ! validate_integer "CONNECTION_TIMEOUT" "$connection_timeout" 1 300; then
        ((errors++))
    fi
    
    if ! validate_integer "TEST_TIMEOUT" "$test_timeout" 5 1800; then
        ((errors++))
    fi
    
    # Retry configuration validation
    if ! validate_integer "MAX_RETRIES" "$max_retries" 0 20; then
        ((errors++))
    fi
    
    if ! validate_float "RETRY_DELAY" "$retry_delay" 0.1 30.0; then
        ((errors++))
    fi
    
    # Log level validation
    local valid_log_levels="DEBUG INFO WARNING ERROR CRITICAL"
    if [[ " $valid_log_levels " != *" $log_level "* ]]; then
        log_error "Invalid LOG_LEVEL: $log_level. Supported: $valid_log_levels"
        ((errors++))
    fi
    
    # Timeout relationship validation
    if [[ $connection_timeout -ge $test_timeout ]]; then
        log_error "CONNECTION_TIMEOUT ($connection_timeout) should be less than TEST_TIMEOUT ($test_timeout)"
        ((errors++))
    fi
    
    # Protocol compatibility check
    if ! check_protocol_compatibility "$transport" "$security" "$muxer" "$is_dialer"; then
        ((errors++))
    fi
    
    # Performance warnings
    if [[ $max_retries -gt 10 ]]; then
        log_info "WARNING: High retry count ($max_retries) may cause long test execution times"
    fi
    
    if [[ $connection_timeout -gt 60 ]]; then
        log_info "WARNING: Long connection timeout ($connection_timeout s) may cause slow test failures"
    fi
    
    if [[ "$log_level" == "DEBUG" ]]; then
        log_info "WARNING: DEBUG logging enabled - may impact performance"
    fi
    
    # Environment-specific warnings
    local node_env="${NODE_ENV:-development}"
    if [[ "$node_env" == "production" ]]; then
        if [[ $port -eq 0 ]]; then
            log_info "WARNING: Using random port in production - ensure proper service discovery"
        fi
        
        if [[ "$host" == "0.0.0.0" ]]; then
            log_info "WARNING: Binding to all interfaces in production - ensure proper firewall configuration"
        fi
    fi
    
    return $errors
}

validate_js_server_config() {
    log_info "Validating JS Echo Server configuration..."
    
    # Check if Node.js is available
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js is not installed or not in PATH"
        return 1
    fi
    
    local node_version
    node_version=$(node --version)
    log_debug "Node.js version: $node_version"
    
    # Check if the config validator exists
    local config_validator="$PROJECT_ROOT/images/js-echo-server/src/config-validator.js"
    if [[ ! -f "$config_validator" ]]; then
        log_error "Configuration validator not found: $config_validator"
        return 1
    fi
    
    # Run JS-specific validation
    log_debug "Running JS-specific configuration validation..."
    
    # Create a temporary validation script with proper .js extension
    local temp_script
    temp_script=$(mktemp)
    mv "$temp_script" "${temp_script}.js"
    temp_script="${temp_script}.js"
    
    cat > "$temp_script" << EOF
import { validateConfiguration } from '$config_validator';

const config = {
  transport: process.env.TRANSPORT || 'tcp',
  security: process.env.SECURITY || 'noise',
  muxer: process.env.MUXER || 'yamux',
  isDialer: (process.env.IS_DIALER || 'true') === 'true',
  host: process.env.HOST || '0.0.0.0',
  port: parseInt(process.env.PORT || '0', 10),
  redisAddr: process.env.REDIS_ADDR || 'redis://localhost:6379'
};

const validation = validateConfiguration(config);

if (validation.info.length > 0) {
  console.error('[INFO] Configuration information:');
  validation.info.forEach(info => console.error(\`[INFO]   \${info}\`));
}

if (validation.warnings.length > 0) {
  console.error('[WARN] Configuration warnings:');
  validation.warnings.forEach(warning => console.error(\`[WARN]   \${warning}\`));
}

if (validation.errors.length > 0) {
  console.error('[ERROR] Configuration validation failed:');
  validation.errors.forEach(error => console.error(\`[ERROR]   \${error}\`));
  process.exit(1);
}

console.error('[INFO] JS-specific configuration validation passed');
process.exit(0);
EOF
    
    # Run the validation
    local js_validation_result=0
    if ! (cd "$PROJECT_ROOT/images/js-echo-server/src" && node "$temp_script"); then
        js_validation_result=1
    fi
    
    # Cleanup
    rm -f "$temp_script"
    
    return $js_validation_result
}

validate_python_config() {
    log_info "Validating Python Test Harness configuration..."
    
    # Check if Python is available
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python 3 is not installed or not in PATH"
        return 1
    fi
    
    local python_version
    python_version=$(python3 --version)
    log_debug "Python version: $python_version"
    
    # Check if the config module exists
    local config_module="$PROJECT_ROOT/images/py-test-harness/src/config.py"
    if [[ ! -f "$config_module" ]]; then
        log_error "Configuration module not found: $config_module"
        return 1
    fi
    
    # Run Python-specific validation
    log_debug "Running Python-specific configuration validation..."
    
    # Create a temporary validation script in the src directory
    local temp_script="$PROJECT_ROOT/images/py-test-harness/src/validate_config_temp.py"
    
    cat > "$temp_script" << 'EOF'
import sys
import os

try:
    from config import TestConfig
    
    # Create config from environment
    config = TestConfig.from_env()
    
    # Validate configuration
    config.validate_config()
    
    print("[INFO] Python-specific configuration validation passed", file=sys.stderr)
    sys.exit(0)
    
except Exception as e:
    print(f"[ERROR] Python configuration validation failed: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
EOF
    
    # Run the validation
    local py_validation_result=0
    if ! (cd "$PROJECT_ROOT/images/py-test-harness/src" && python3 validate_config_temp.py); then
        py_validation_result=1
    fi
    
    # Cleanup
    rm -f "$temp_script"
    
    return $py_validation_result
}

print_configuration_summary() {
    log_info "Configuration Summary:"
    log_info "  Protocol Stack: ${TRANSPORT:-tcp}/${SECURITY:-noise}/${MUXER:-yamux}"
    log_info "  Role: $([ "${IS_DIALER:-true}" == "true" ] && echo "dialer" || echo "listener")"
    log_info "  Network: ${HOST:-0.0.0.0}:${PORT:-0}"
    log_info "  Redis: ${REDIS_ADDR:-redis:6379}"
    log_info "  Timeouts: conn=${CONNECTION_TIMEOUT:-10}s, test=${TEST_TIMEOUT:-30}s, redis=${REDIS_TIMEOUT:-30}s"
    log_info "  Retries: max=${MAX_RETRIES:-3}, delay=${RETRY_DELAY:-1.0}s"
    log_info "  Logging: ${LOG_LEVEL:-INFO}"
    log_info "  Environment: ${NODE_ENV:-development}"
}

main() {
    local validation_errors=0
    
    log_info "Starting comprehensive configuration validation..."
    
    # Print configuration summary
    print_configuration_summary
    
    # Validate environment configuration
    if ! validate_environment_config; then
        ((validation_errors++))
    fi
    
    # Validate JS server configuration if requested
    if [[ "${VALIDATE_JS:-true}" == "true" ]]; then
        if ! validate_js_server_config; then
            ((validation_errors++))
        fi
    fi
    
    # Validate Python configuration if requested
    if [[ "${VALIDATE_PYTHON:-true}" == "true" ]]; then
        if ! validate_python_config; then
            ((validation_errors++))
        fi
    fi
    
    # Final result
    if [[ $validation_errors -eq 0 ]]; then
        log_info "All configuration validations passed successfully"
        return 0
    else
        log_error "Configuration validation failed with $validation_errors error(s)"
        return 1
    fi
}

# Handle command line arguments
case "${1:-validate}" in
    "validate")
        main
        ;;
    "js-only")
        VALIDATE_PYTHON=false
        main
        ;;
    "python-only")
        VALIDATE_JS=false
        main
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [validate|js-only|python-only|help]"
        echo ""
        echo "Commands:"
        echo "  validate     - Validate all configurations (default)"
        echo "  js-only      - Validate only JS server configuration"
        echo "  python-only  - Validate only Python client configuration"
        echo "  help         - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  DEBUG=true   - Enable debug logging"
        echo "  All standard test configuration variables (TRANSPORT, SECURITY, etc.)"
        exit 0
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac