#!/usr/bin/env bash

# Health Check Script for JS-libp2p Echo Interop Components
# Provides health checking for both JS Echo Server and Python Test Harness

set -euo pipefail

# Configuration
COMPONENT="${1:-unknown}"
TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"
REDIS_ADDR="${REDIS_ADDR:-redis:6379}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "[INFO] $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Health check for JS Echo Server
check_js_server() {
    log_info "Checking JS Echo Server health..."
    
    # Check if Node.js is available
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js not found"
        return 1
    fi
    
    # Check if the main script exists
    if [[ ! -f "/app/src/index.js" ]]; then
        log_error "Main script not found: /app/src/index.js"
        return 1
    fi
    
    # Check if package.json exists and has required dependencies
    if [[ ! -f "/app/package.json" ]]; then
        log_error "package.json not found"
        return 1
    fi
    
    # Check if node_modules exists (dependencies installed)
    if [[ ! -d "/app/node_modules" ]]; then
        log_error "node_modules not found - dependencies not installed"
        return 1
    fi
    
    # Check if required dependencies are available
    local required_deps=("@libp2p/tcp" "@libp2p/noise" "@chainsafe/libp2p-yamux" "redis")
    for dep in "${required_deps[@]}"; do
        if [[ ! -d "/app/node_modules/$dep" ]]; then
            log_warning "Dependency not found: $dep"
        fi
    done
    
    # Check if Redis connection is possible (if Redis address is provided)
    if [[ -n "$REDIS_ADDR" ]] && command -v nc >/dev/null 2>&1; then
        local redis_host="${REDIS_ADDR%:*}"
        local redis_port="${REDIS_ADDR#*:}"
        
        if ! timeout 5 nc -z "$redis_host" "$redis_port" 2>/dev/null; then
            log_warning "Cannot connect to Redis at $REDIS_ADDR"
        else
            log_info "Redis connection available at $REDIS_ADDR"
        fi
    fi
    
    # Check if the process is running (if PID file exists)
    if [[ -f "/tmp/js-echo-server.pid" ]]; then
        local pid=$(cat /tmp/js-echo-server.pid)
        if kill -0 "$pid" 2>/dev/null; then
            log_info "JS Echo Server process is running (PID: $pid)"
        else
            log_warning "PID file exists but process is not running"
        fi
    fi
    
    log_success "JS Echo Server health check passed"
    return 0
}

# Health check for Python Test Harness
check_py_client() {
    log_info "Checking Python Test Harness health..."
    
    # Check if Python is available
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "Python3 not found"
        return 1
    fi
    
    # Check Python version
    local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
    log_info "Python version: $python_version"
    
    # Check if the main script exists
    if [[ ! -f "/app/src/main.py" ]]; then
        log_error "Main script not found: /app/src/main.py"
        return 1
    fi
    
    # Check if requirements.txt exists
    if [[ ! -f "/app/requirements.txt" ]]; then
        log_error "requirements.txt not found"
        return 1
    fi
    
    # Check if required Python packages are installed
    local required_packages=("trio" "pytest" "hypothesis" "structlog" "redis")
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" 2>/dev/null; then
            log_warning "Python package not available: $package"
        else
            log_info "Python package available: $package"
        fi
    done
    
    # Check if Redis connection is possible
    if [[ -n "$REDIS_ADDR" ]]; then
        if python3 -c "
import redis
import sys
try:
    r = redis.Redis.from_url('redis://$REDIS_ADDR')
    r.ping()
    print('Redis connection successful')
except Exception as e:
    print(f'Redis connection failed: {e}')
    sys.exit(1)
" 2>/dev/null; then
            log_info "Redis connection test passed"
        else
            log_warning "Redis connection test failed"
        fi
    fi
    
    # Check if test files exist
    local test_files=(
        "/app/src/test_echo_protocol.py"
        "/app/src/test_echo_properties.py"
        "/app/src/test_error_handling_properties.py"
    )
    
    for test_file in "${test_files[@]}"; do
        if [[ -f "$test_file" ]]; then
            log_info "Test file found: $(basename "$test_file")"
        else
            log_warning "Test file not found: $test_file"
        fi
    done
    
    log_success "Python Test Harness health check passed"
    return 0
}

# Health check for Redis
check_redis() {
    log_info "Checking Redis health..."
    
    if command -v redis-cli >/dev/null 2>&1; then
        if redis-cli ping >/dev/null 2>&1; then
            log_success "Redis is responding to ping"
            return 0
        else
            log_error "Redis is not responding to ping"
            return 1
        fi
    else
        log_warning "redis-cli not available, cannot check Redis health"
        return 1
    fi
}

# Generic health check
check_generic() {
    log_info "Running generic health check..."
    
    # Check basic system health
    local checks_passed=0
    local total_checks=0
    
    # Check disk space
    total_checks=$((total_checks + 1))
    local disk_usage=$(df / | tail -n1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 90 ]]; then
        log_info "Disk usage OK: ${disk_usage}%"
        checks_passed=$((checks_passed + 1))
    else
        log_warning "High disk usage: ${disk_usage}%"
    fi
    
    # Check memory usage
    total_checks=$((total_checks + 1))
    if command -v free >/dev/null 2>&1; then
        local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        if [[ $mem_usage -lt 90 ]]; then
            log_info "Memory usage OK: ${mem_usage}%"
            checks_passed=$((checks_passed + 1))
        else
            log_warning "High memory usage: ${mem_usage}%"
        fi
    else
        log_warning "Cannot check memory usage (free command not available)"
    fi
    
    # Check if we're in a container
    total_checks=$((total_checks + 1))
    if [[ -f "/.dockerenv" ]]; then
        log_info "Running in Docker container"
        checks_passed=$((checks_passed + 1))
    else
        log_info "Not running in Docker container"
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check network connectivity (if possible)
    total_checks=$((total_checks + 1))
    if command -v ping >/dev/null 2>&1; then
        if timeout 3 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_info "Network connectivity OK"
            checks_passed=$((checks_passed + 1))
        else
            log_warning "Network connectivity test failed"
        fi
    else
        log_warning "Cannot test network connectivity (ping not available)"
    fi
    
    log_info "Generic health check: $checks_passed/$total_checks checks passed"
    
    if [[ $checks_passed -ge $((total_checks / 2)) ]]; then
        log_success "Generic health check passed"
        return 0
    else
        log_error "Generic health check failed"
        return 1
    fi
}

# Main health check function
main() {
    log_info "Starting health check for component: $COMPONENT"
    
    case "$COMPONENT" in
        "js-server"|"js-echo-server")
            check_js_server
            ;;
        "py-client"|"py-test-harness"|"python-client")
            check_py_client
            ;;
        "redis")
            check_redis
            ;;
        "generic"|"unknown")
            check_generic
            ;;
        *)
            log_error "Unknown component: $COMPONENT"
            log_info "Supported components: js-server, py-client, redis, generic"
            return 1
            ;;
    esac
}

# Handle timeout
timeout_handler() {
    log_error "Health check timed out after ${TIMEOUT}s"
    exit 1
}

# Set up timeout
trap timeout_handler SIGALRM
(sleep "$TIMEOUT" && kill -ALRM $$) &
timeout_pid=$!

# Run health check
if main; then
    kill $timeout_pid 2>/dev/null || true
    log_success "Health check completed successfully"
    exit 0
else
    kill $timeout_pid 2>/dev/null || true
    log_error "Health check failed"
    exit 1
fi