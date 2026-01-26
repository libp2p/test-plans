#!/usr/bin/env bash

# Validation script for Docker Compose configuration
# Tests that all compose files are valid and services can be started

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker and Docker Compose are available
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    log_info "Dependencies check passed"
}

# Validate Docker Compose file syntax
validate_compose_files() {
    log_info "Validating Docker Compose file syntax..."
    
    local files=(
        "docker-compose.yml"
        "docker-compose.dev.yml"
        "docker-compose.test.yml"
        "docker-compose.prod.yml"
        "docker-compose.protocols.yml"
        "docker-compose.redis.yml"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Validating $file..."
            if docker-compose -f "$file" config >/dev/null 2>&1; then
                log_info "✓ $file is valid"
            else
                log_error "✗ $file has syntax errors"
                docker-compose -f "$file" config
                exit 1
            fi
        else
            log_warn "File $file not found, skipping"
        fi
    done
    
    log_info "All Docker Compose files are valid"
}

# Test basic compose configuration
test_basic_config() {
    log_info "Testing basic Docker Compose configuration..."
    
    # Test main configuration
    if docker-compose config >/dev/null 2>&1; then
        log_info "✓ Main configuration is valid"
    else
        log_error "✗ Main configuration has errors"
        docker-compose config
        exit 1
    fi
    
    # Test combined configurations
    local combinations=(
        "docker-compose.yml docker-compose.dev.yml"
        "docker-compose.yml docker-compose.test.yml"
        "docker-compose.yml docker-compose.prod.yml"
        "docker-compose.yml docker-compose.protocols.yml"
    )
    
    for combo in "${combinations[@]}"; do
        log_info "Testing combination: $combo"
        if docker-compose -f ${combo} config >/dev/null 2>&1; then
            log_info "✓ Combination valid: $combo"
        else
            log_error "✗ Combination invalid: $combo"
            docker-compose -f ${combo} config
            exit 1
        fi
    done
}

# Test service definitions
test_service_definitions() {
    log_info "Testing service definitions..."
    
    # Check that required services are defined
    local required_services=("redis" "js-echo-server" "py-test-harness")
    
    for service in "${required_services[@]}"; do
        if docker-compose config --services | grep -q "^${service}$"; then
            log_info "✓ Service '$service' is defined"
        else
            log_error "✗ Required service '$service' is not defined"
            exit 1
        fi
    done
    
    # Check network configuration
    if docker-compose config | grep -q "js-libp2p-echo-interop"; then
        log_info "✓ Network 'js-libp2p-echo-interop' is configured"
    else
        log_error "✗ Required network 'js-libp2p-echo-interop' is not configured"
        exit 1
    fi
}

# Test environment variable handling
test_environment_variables() {
    log_info "Testing environment variable handling..."
    
    # Test with different environment configurations
    local test_configs=(
        "TRANSPORT=tcp SECURITY=noise MUXER=yamux"
        "TRANSPORT=tcp SECURITY=noise MUXER=mplex"
        "DEBUG=true NODE_ENV=development"
    )
    
    for config in "${test_configs[@]}"; do
        log_info "Testing with: $config"
        if env $config docker-compose config >/dev/null 2>&1; then
            log_info "✓ Configuration valid: $config"
        else
            log_error "✗ Configuration invalid: $config"
            env $config docker-compose config
            exit 1
        fi
    done
}

# Test profile configurations
test_profiles() {
    log_info "Testing Docker Compose profiles..."
    
    # Test test profiles
    local test_profiles=("basic" "binary" "large" "concurrent" "all-tests")
    
    for profile in "${test_profiles[@]}"; do
        log_info "Testing profile: $profile"
        if docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile "$profile" config >/dev/null 2>&1; then
            log_info "✓ Profile '$profile' is valid"
        else
            log_error "✗ Profile '$profile' is invalid"
            exit 1
        fi
    done
    
    # Test protocol profiles
    local protocol_profiles=("tcp-noise-yamux" "tcp-noise-mplex" "all-protocols")
    
    for profile in "${protocol_profiles[@]}"; do
        log_info "Testing protocol profile: $profile"
        if docker-compose -f docker-compose.yml -f docker-compose.protocols.yml --profile "$profile" config >/dev/null 2>&1; then
            log_info "✓ Protocol profile '$profile' is valid"
        else
            log_error "✗ Protocol profile '$profile' is invalid"
            exit 1
        fi
    done
}

# Test build contexts
test_build_contexts() {
    log_info "Testing build contexts..."
    
    # Check that build contexts exist
    local build_contexts=(
        "images/js-echo-server"
        "images/py-test-harness"
    )
    
    for context in "${build_contexts[@]}"; do
        if [[ -d "$context" ]]; then
            log_info "✓ Build context exists: $context"
            
            # Check for Dockerfile
            if [[ -f "$context/Dockerfile" ]]; then
                log_info "✓ Dockerfile exists: $context/Dockerfile"
            else
                log_error "✗ Dockerfile missing: $context/Dockerfile"
                exit 1
            fi
        else
            log_error "✗ Build context missing: $context"
            exit 1
        fi
    done
}

# Test network connectivity (requires containers to be running)
test_network_connectivity() {
    log_info "Testing network connectivity (requires running containers)..."
    
    # This is an optional test that requires containers to be running
    if docker-compose ps | grep -q "Up"; then
        log_info "Containers are running, testing connectivity..."
        
        # Test Redis connectivity
        if docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; then
            log_info "✓ Redis is accessible"
        else
            log_warn "Redis connectivity test failed (containers may not be fully started)"
        fi
    else
        log_info "No running containers found, skipping connectivity tests"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    docker-compose down --remove-orphans --volumes >/dev/null 2>&1 || true
}

# Main validation function
main() {
    log_info "Starting Docker Compose validation..."
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Run validation steps
    check_dependencies
    validate_compose_files
    test_basic_config
    test_service_definitions
    test_environment_variables
    test_profiles
    test_build_contexts
    
    # Optional connectivity test
    if [[ "${1:-}" == "--test-connectivity" ]]; then
        test_network_connectivity
    fi
    
    log_info "All Docker Compose validation tests passed!"
    log_info ""
    log_info "You can now run the tests with:"
    log_info "  make compose-test"
    log_info "  make compose-dev"
    log_info "  docker-compose up --build"
}

# Show usage if help requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--test-connectivity]"
    echo ""
    echo "Validates Docker Compose configuration for JS-libp2p Echo Interop Tests"
    echo ""
    echo "Options:"
    echo "  --test-connectivity  Also test network connectivity (requires running containers)"
    echo "  --help, -h          Show this help message"
    exit 0
fi

# Run main function
main "$@"