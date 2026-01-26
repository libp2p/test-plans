#!/usr/bin/env bash

# Local Build Script for JS-libp2p Echo Interop Tests
# Builds Docker images and verifies the test environment locally

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CACHE="${BUILD_CACHE:-true}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
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
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_tools+=("docker")
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        missing_tools+=("docker-compose")
    fi
    
    # Check Node.js
    if ! command -v node >/dev/null 2>&1; then
        missing_tools+=("node")
    fi
    
    # Check Python
    if ! command -v python3 >/dev/null 2>&1; then
        missing_tools+=("python3")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        return 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    log_success "All prerequisites are available"
    return 0
}

# Build JS Echo Server image
build_js_server() {
    log_info "Building JS Echo Server Docker image..."
    
    local build_args=()
    if [[ "$BUILD_CACHE" == "false" ]]; then
        build_args+=("--no-cache")
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        build_args+=("--progress=plain")
    fi
    
    cd "$PROJECT_ROOT/images/js-echo-server"
    
    if docker build "${build_args[@]}" -t js-libp2p-echo-server:latest .; then
        log_success "JS Echo Server image built successfully"
    else
        log_error "Failed to build JS Echo Server image"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Build Python Test Harness image
build_py_client() {
    log_info "Building Python Test Harness Docker image..."
    
    local build_args=()
    if [[ "$BUILD_CACHE" == "false" ]]; then
        build_args+=("--no-cache")
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        build_args+=("--progress=plain")
    fi
    
    cd "$PROJECT_ROOT/images/py-test-harness"
    
    if docker build "${build_args[@]}" -t py-test-harness:latest .; then
        log_success "Python Test Harness image built successfully"
    else
        log_error "Failed to build Python Test Harness image"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Verify image functionality
verify_images() {
    log_info "Verifying Docker images..."
    
    # Test JS Echo Server image
    log_debug "Testing JS Echo Server image..."
    if docker run --rm js-libp2p-echo-server:latest node --version >/dev/null 2>&1; then
        log_success "JS Echo Server image is functional"
    else
        log_error "JS Echo Server image verification failed"
        return 1
    fi
    
    # Test Python Test Harness image
    log_debug "Testing Python Test Harness image..."
    if docker run --rm py-test-harness:latest python3 --version >/dev/null 2>&1; then
        log_success "Python Test Harness image is functional"
    else
        log_error "Python Test Harness image verification failed"
        return 1
    fi
}

# Run configuration validation
validate_configuration() {
    log_info "Validating configuration..."
    
    cd "$PROJECT_ROOT"
    
    # Run configuration validation script
    if [[ -f "lib/validate-config.sh" ]]; then
        if TRANSPORT=tcp SECURITY=noise MUXER=yamux ./lib/validate-config.sh; then
            log_success "Configuration validation passed"
        else
            log_error "Configuration validation failed"
            return 1
        fi
    else
        log_warning "Configuration validation script not found, skipping"
    fi
}

# Run unit tests
run_unit_tests() {
    log_info "Running unit tests..."
    
    # Run JS unit tests
    log_debug "Running JS Echo Server unit tests..."
    cd "$PROJECT_ROOT/images/js-echo-server"
    
    if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
        if npm test; then
            log_success "JS unit tests passed"
        else
            log_error "JS unit tests failed"
            return 1
        fi
    else
        log_warning "No JS unit tests found, skipping"
    fi
    
    # Run Python unit tests
    log_debug "Running Python Test Harness unit tests..."
    cd "$PROJECT_ROOT/images/py-test-harness"
    
    if [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
        if python3 -m pytest src/ -v --tb=short -x; then
            log_success "Python unit tests passed"
        else
            log_error "Python unit tests failed"
            return 1
        fi
    else
        log_warning "No Python unit tests found, skipping"
    fi
    
    cd "$PROJECT_ROOT"
}

# Generate build report
generate_build_report() {
    log_info "Generating build report..."
    
    local report_file="$PROJECT_ROOT/build-report.json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Get image information
    local js_image_id
    local py_image_id
    js_image_id=$(docker images --format "{{.ID}}" js-libp2p-echo-server:latest | head -n1)
    py_image_id=$(docker images --format "{{.ID}}" py-test-harness:latest | head -n1)
    
    # Get image sizes
    local js_image_size
    local py_image_size
    js_image_size=$(docker images --format "{{.Size}}" js-libp2p-echo-server:latest | head -n1)
    py_image_size=$(docker images --format "{{.Size}}" py-test-harness:latest | head -n1)
    
    # Get Node.js and Python versions
    local node_version
    local python_version
    node_version=$(docker run --rm js-libp2p-echo-server:latest node --version 2>/dev/null || echo "unknown")
    python_version=$(docker run --rm py-test-harness:latest python3 --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
    
    cat > "$report_file" << EOF
{
  "build_timestamp": "$timestamp",
  "build_status": "success",
  "images": {
    "js-echo-server": {
      "tag": "js-libp2p-echo-server:latest",
      "image_id": "$js_image_id",
      "size": "$js_image_size",
      "node_version": "$node_version"
    },
    "py-test-harness": {
      "tag": "py-test-harness:latest",
      "image_id": "$py_image_id",
      "size": "$py_image_size",
      "python_version": "$python_version"
    }
  },
  "environment": {
    "docker_version": "$(docker --version | cut -d' ' -f3 | tr -d ',')",
    "docker_compose_version": "$(docker-compose --version | cut -d' ' -f3 | tr -d ',')",
    "host_os": "$(uname -s)",
    "host_arch": "$(uname -m)"
  },
  "build_options": {
    "cache_enabled": $BUILD_CACHE,
    "verbose": $VERBOSE
  }
}
EOF
    
    log_success "Build report generated: $report_file"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Remove dangling images
    if docker images -f "dangling=true" -q | grep -q .; then
        log_debug "Removing dangling images..."
        docker rmi $(docker images -f "dangling=true" -q) >/dev/null 2>&1 || true
    fi
    
    # Prune build cache if requested
    if [[ "${CLEANUP_CACHE:-false}" == "true" ]]; then
        log_debug "Pruning Docker build cache..."
        docker builder prune -f >/dev/null 2>&1 || true
    fi
}

# Main build function
main() {
    log_info "Starting local build for JS-libp2p Echo Interop Tests"
    log_info "Project root: $PROJECT_ROOT"
    log_info "Build cache: $BUILD_CACHE"
    log_info "Verbose: $VERBOSE"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Execute build steps
    check_prerequisites || exit 1
    validate_configuration || exit 1
    build_js_server || exit 1
    build_py_client || exit 1
    verify_images || exit 1
    run_unit_tests || exit 1
    generate_build_report || exit 1
    
    log_success "Local build completed successfully!"
    log_info "Docker images built:"
    log_info "  - js-libp2p-echo-server:latest"
    log_info "  - py-test-harness:latest"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run integration tests: ./scripts/test-local.sh"
    log_info "  2. Start test environment: docker-compose up"
    log_info "  3. View build report: cat build-report.json"
}

# Handle command line arguments
case "${1:-build}" in
    "build")
        main
        ;;
    "clean")
        log_info "Cleaning up Docker images and cache..."
        docker rmi js-libp2p-echo-server:latest py-test-harness:latest 2>/dev/null || true
        docker builder prune -f >/dev/null 2>&1 || true
        log_success "Cleanup completed"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [build|clean|help]"
        echo ""
        echo "Commands:"
        echo "  build  - Build Docker images and run verification (default)"
        echo "  clean  - Remove built images and clean cache"
        echo "  help   - Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  BUILD_CACHE=false    - Disable Docker build cache"
        echo "  VERBOSE=true         - Enable verbose output"
        echo "  CLEANUP_CACHE=true   - Clean Docker build cache after build"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac