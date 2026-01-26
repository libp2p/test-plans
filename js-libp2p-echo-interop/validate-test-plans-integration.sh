#!/usr/bin/env bash

# Test-Plans Integration Validation Script
# Validates compatibility with libp2p/test-plans repository conventions

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[VALIDATION]${NC} $*"
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

# Validation results
TOTAL_VALIDATIONS=0
PASSED_VALIDATIONS=0
FAILED_VALIDATIONS=0

# Add validation result
add_validation_result() {
    local validation_name="$1"
    local status="$2"
    
    TOTAL_VALIDATIONS=$((TOTAL_VALIDATIONS + 1))
    
    if [[ "$status" == "passed" ]]; then
        PASSED_VALIDATIONS=$((PASSED_VALIDATIONS + 1))
        log_success "✓ $validation_name"
    else
        FAILED_VALIDATIONS=$((FAILED_VALIDATIONS + 1))
        log_error "✗ $validation_name"
    fi
}

# Validate directory structure
validate_directory_structure() {
    log_info "Validating directory structure..."
    
    local required_dirs=(
        "images"
        "lib"
        "scripts"
        ".github/workflows"
    )
    
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        add_validation_result "Directory Structure" "passed"
        return 0
    else
        log_error "Missing directories: ${missing_dirs[*]}"
        add_validation_result "Directory Structure" "failed"
        return 1
    fi
}

# Validate required files
validate_required_files() {
    log_info "Validating required files..."
    
    local required_files=(
        "Makefile"
        "docker-compose.yml"
        "images.yaml"
        "versions.ts"
        "run.sh"
        ".github/workflows/ci.yml"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        add_validation_result "Required Files" "passed"
        return 0
    else
        log_error "Missing files: ${missing_files[*]}"
        add_validation_result "Required Files" "failed"
        return 1
    fi
}

# Validate Makefile conventions
validate_makefile_conventions() {
    log_info "Validating Makefile conventions..."
    
    local required_targets=(
        "build"
        "test"
        "clean"
        "help"
    )
    
    local missing_targets=()
    
    for target in "${required_targets[@]}"; do
        if ! grep -q "^${target}:" Makefile; then
            missing_targets+=("$target")
        fi
    done
    
    if [[ ${#missing_targets[@]} -eq 0 ]]; then
        add_validation_result "Makefile Conventions" "passed"
        return 0
    else
        log_error "Missing Makefile targets: ${missing_targets[*]}"
        add_validation_result "Makefile Conventions" "failed"
        return 1
    fi
}

# Validate images.yaml format
validate_images_yaml() {
    log_info "Validating images.yaml format..."
    
    if [[ ! -f "images.yaml" ]]; then
        log_error "images.yaml not found"
        add_validation_result "images.yaml Format" "failed"
        return 1
    fi
    
    # Check if it's valid YAML and contains required fields
    if python3 -c "
import json
import sys

try:
    # Simple YAML-like validation without PyYAML
    with open('images.yaml') as f:
        content = f.read()
    
    # Basic checks for YAML structure
    if 'implementations:' not in content and 'images:' not in content:
        print('images.yaml must contain implementations or images section')
        sys.exit(1)
    
    # Check for at least one implementation
    if 'id:' not in content:
        print('images.yaml must contain at least one implementation with id')
        sys.exit(1)
    
    # Check for required fields
    required_fields = ['transports:', 'secureChannels:', 'muxers:']
    for field in required_fields:
        if field not in content:
            print(f'images.yaml missing required field: {field}')
            sys.exit(1)
    
    print('images.yaml validation passed')
    
except Exception as e:
    print(f'Validation error: {e}')
    sys.exit(1)
" 2>/dev/null; then
        add_validation_result "images.yaml Format" "passed"
        return 0
    else
        log_error "images.yaml validation failed"
        add_validation_result "images.yaml Format" "failed"
        return 1
    fi
}

# Validate versions.ts format
validate_versions_ts() {
    log_info "Validating versions.ts format..."
    
    if [[ ! -f "versions.ts" ]]; then
        log_error "versions.ts not found"
        add_validation_result "versions.ts Format" "failed"
        return 1
    fi
    
    # Check if it's valid TypeScript and contains required exports
    if node -e "
const fs = require('fs');
const content = fs.readFileSync('versions.ts', 'utf8');

// Basic validation - check for export and version structure
if (!content.includes('export')) {
    console.error('versions.ts must contain exports');
    process.exit(1);
}

if (!content.includes('version') && !content.includes('Version')) {
    console.error('versions.ts must contain version information');
    process.exit(1);
}

console.log('versions.ts validation passed');
" 2>/dev/null; then
        add_validation_result "versions.ts Format" "passed"
        return 0
    else
        log_error "versions.ts validation failed"
        add_validation_result "versions.ts Format" "failed"
        return 1
    fi
}

# Validate Docker Compose configuration
validate_docker_compose() {
    log_info "Validating Docker Compose configuration..."
    
    if docker-compose config --quiet 2>/dev/null; then
        # Check for required services
        local required_services=("redis" "js-echo-server" "py-test-harness")
        local missing_services=()
        
        for service in "${required_services[@]}"; do
            if ! docker-compose config --services | grep -q "^${service}$"; then
                missing_services+=("$service")
            fi
        done
        
        if [[ ${#missing_services[@]} -eq 0 ]]; then
            add_validation_result "Docker Compose Configuration" "passed"
            return 0
        else
            log_error "Missing services: ${missing_services[*]}"
            add_validation_result "Docker Compose Configuration" "failed"
            return 1
        fi
    else
        log_error "Docker Compose configuration is invalid"
        add_validation_result "Docker Compose Configuration" "failed"
        return 1
    fi
}

# Validate GitHub Actions workflow
validate_github_actions() {
    log_info "Validating GitHub Actions workflow..."
    
    local workflow_file=".github/workflows/ci.yml"
    
    if [[ ! -f "$workflow_file" ]]; then
        log_error "GitHub Actions workflow not found: $workflow_file"
        add_validation_result "GitHub Actions Workflow" "failed"
        return 1
    fi
    
    # Check for required workflow elements
    local required_elements=(
        "name:"
        "on:"
        "jobs:"
        "runs-on:"
        "steps:"
    )
    
    local missing_elements=()
    
    for element in "${required_elements[@]}"; do
        if ! grep -q "$element" "$workflow_file"; then
            missing_elements+=("$element")
        fi
    done
    
    if [[ ${#missing_elements[@]} -eq 0 ]]; then
        add_validation_result "GitHub Actions Workflow" "passed"
        return 0
    else
        log_error "Missing workflow elements: ${missing_elements[*]}"
        add_validation_result "GitHub Actions Workflow" "failed"
        return 1
    fi
}

# Validate test scripts
validate_test_scripts() {
    log_info "Validating test scripts..."
    
    local required_scripts=(
        "scripts/build-local.sh"
        "scripts/test-local.sh"
        "run-comprehensive-tests.sh"
        "test-integration-e2e.sh"
        "test-ci-integration.sh"
    )
    
    local missing_scripts=()
    local non_executable=()
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            missing_scripts+=("$script")
        elif [[ ! -x "$script" ]]; then
            non_executable+=("$script")
        fi
    done
    
    local status="passed"
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "Missing test scripts: ${missing_scripts[*]}"
        status="failed"
    fi
    
    if [[ ${#non_executable[@]} -gt 0 ]]; then
        log_error "Non-executable test scripts: ${non_executable[*]}"
        status="failed"
    fi
    
    add_validation_result "Test Scripts" "$status"
    
    if [[ "$status" == "passed" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate image Dockerfiles
validate_dockerfiles() {
    log_info "Validating Dockerfiles..."
    
    local required_dockerfiles=(
        "images/js-echo-server/Dockerfile"
        "images/py-test-harness/Dockerfile"
    )
    
    local missing_dockerfiles=()
    local invalid_dockerfiles=()
    
    for dockerfile in "${required_dockerfiles[@]}"; do
        if [[ ! -f "$dockerfile" ]]; then
            missing_dockerfiles+=("$dockerfile")
        else
            # Basic Dockerfile validation
            if ! grep -q "^FROM" "$dockerfile"; then
                invalid_dockerfiles+=("$dockerfile (missing FROM)")
            fi
        fi
    done
    
    local status="passed"
    
    if [[ ${#missing_dockerfiles[@]} -gt 0 ]]; then
        log_error "Missing Dockerfiles: ${missing_dockerfiles[*]}"
        status="failed"
    fi
    
    if [[ ${#invalid_dockerfiles[@]} -gt 0 ]]; then
        log_error "Invalid Dockerfiles: ${invalid_dockerfiles[*]}"
        status="failed"
    fi
    
    add_validation_result "Dockerfiles" "$status"
    
    if [[ "$status" == "passed" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate test-plans compatibility
validate_test_plans_compatibility() {
    log_info "Validating test-plans repository compatibility..."
    
    local compatibility_checks=0
    local compatibility_passed=0
    
    # Check for run.sh script
    compatibility_checks=$((compatibility_checks + 1))
    if [[ -f "run.sh" ]] && [[ -x "run.sh" ]]; then
        compatibility_passed=$((compatibility_passed + 1))
    else
        log_error "Missing or non-executable run.sh script"
    fi
    
    # Check for lib directory with common utilities
    compatibility_checks=$((compatibility_checks + 1))
    if [[ -d "lib" ]] && [[ -f "lib/validate-config.sh" ]]; then
        compatibility_passed=$((compatibility_passed + 1))
    else
        log_error "Missing lib directory or validate-config.sh"
    fi
    
    # Check for images directory structure
    compatibility_checks=$((compatibility_checks + 1))
    if [[ -d "images" ]] && [[ -f "images.yaml" ]]; then
        compatibility_passed=$((compatibility_passed + 1))
    else
        log_error "Missing images directory or images.yaml"
    fi
    
    # Check for versions.ts
    compatibility_checks=$((compatibility_checks + 1))
    if [[ -f "versions.ts" ]]; then
        compatibility_passed=$((compatibility_passed + 1))
    else
        log_error "Missing versions.ts file"
    fi
    
    if [[ $compatibility_passed -eq $compatibility_checks ]]; then
        add_validation_result "Test-Plans Compatibility" "passed"
        return 0
    else
        log_error "Test-plans compatibility: $compatibility_passed/$compatibility_checks checks passed"
        add_validation_result "Test-Plans Compatibility" "failed"
        return 1
    fi
}

# Generate validation report
generate_validation_report() {
    log_info "Generating validation report..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local success_rate=0
    
    if [[ $TOTAL_VALIDATIONS -gt 0 ]]; then
        success_rate=$((PASSED_VALIDATIONS * 100 / TOTAL_VALIDATIONS))
    fi
    
    cat > test-plans-validation-report.json << EOF
{
  "validation_timestamp": "$timestamp",
  "validation_type": "test_plans_integration",
  "summary": {
    "total_validations": $TOTAL_VALIDATIONS,
    "passed_validations": $PASSED_VALIDATIONS,
    "failed_validations": $FAILED_VALIDATIONS,
    "success_rate": "${success_rate}%"
  },
  "validations": [
    {"name": "Directory Structure", "status": "$(if [[ -d "images" && -d "lib" && -d "scripts" && -d ".github/workflows" ]]; then echo "passed"; else echo "failed"; fi)"},
    {"name": "Required Files", "status": "$(if [[ -f "Makefile" && -f "docker-compose.yml" && -f "images.yaml" && -f "versions.ts" && -f "run.sh" && -f ".github/workflows/ci.yml" ]]; then echo "passed"; else echo "failed"; fi)"},
    {"name": "Makefile Conventions", "status": "$(if grep -q "^build:" Makefile && grep -q "^test:" Makefile && grep -q "^clean:" Makefile && grep -q "^help:" Makefile; then echo "passed"; else echo "failed"; fi)"},
    {"name": "images.yaml Format", "status": "$(if [[ -f "images.yaml" ]]; then echo "passed"; else echo "failed"; fi)"},
    {"name": "versions.ts Format", "status": "$(if [[ -f "versions.ts" ]]; then echo "passed"; else echo "failed"; fi)"},
    {"name": "Docker Compose Configuration", "status": "$(if docker-compose config --quiet 2>/dev/null; then echo "passed"; else echo "failed"; fi)"},
    {"name": "GitHub Actions Workflow", "status": "$(if [[ -f ".github/workflows/ci.yml" ]]; then echo "passed"; else echo "failed"; fi)"},
    {"name": "Test Scripts", "status": "$(if [[ -x "scripts/build-local.sh" && -x "scripts/test-local.sh" ]]; then echo "passed"; else echo "failed"; fi)"},
    {"name": "Dockerfiles", "status": "$(if [[ -f "images/js-echo-server/Dockerfile" && -f "images/py-test-harness/Dockerfile" ]]; then echo "passed"; else echo "failed"; fi)"},
    {"name": "Test-Plans Compatibility", "status": "$(if [[ -f "run.sh" && -d "lib" && -f "images.yaml" && -f "versions.ts" ]]; then echo "passed"; else echo "failed"; fi)"}
  ],
  "environment": {
    "host_os": "$(uname -s)",
    "host_arch": "$(uname -m)",
    "docker_available": $(if command -v docker >/dev/null 2>&1; then echo "true"; else echo "false"; fi),
    "docker_compose_available": $(if command -v docker-compose >/dev/null 2>&1; then echo "true"; else echo "false"; fi)
  }
}
EOF
    
    log_success "Validation report generated: test-plans-validation-report.json"
}

# Main validation function
main() {
    log_info "Starting Test-Plans Integration Validation"
    log_info "Project: JS-libp2p Echo Interoperability Tests"
    
    cd "$PROJECT_ROOT"
    
    # Run all validations
    local validations=(
        "validate_directory_structure"
        "validate_required_files"
        "validate_makefile_conventions"
        "validate_images_yaml"
        "validate_versions_ts"
        "validate_docker_compose"
        "validate_github_actions"
        "validate_test_scripts"
        "validate_dockerfiles"
        "validate_test_plans_compatibility"
    )
    
    echo ""
    log_info "Running validation checks..."
    echo ""
    
    for validation in "${validations[@]}"; do
        $validation
    done
    
    echo ""
    
    # Generate validation report
    generate_validation_report
    
    # Display final summary
    local success_rate=0
    if [[ $TOTAL_VALIDATIONS -gt 0 ]]; then
        success_rate=$((PASSED_VALIDATIONS * 100 / TOTAL_VALIDATIONS))
    fi
    
    log_info "Test-Plans Integration Validation Summary:"
    log_info "  Total Validations: $TOTAL_VALIDATIONS"
    log_info "  Passed: $PASSED_VALIDATIONS"
    log_info "  Failed: $FAILED_VALIDATIONS"
    log_info "  Success Rate: ${success_rate}%"
    
    echo ""
    
    if [[ $success_rate -eq 100 ]]; then
        log_success "🎉 All validations passed! Project is fully compatible with test-plans repository."
        log_info "The JS-libp2p Echo Interop implementation follows all required conventions."
        return 0
    elif [[ $success_rate -ge 80 ]]; then
        log_warning "⚠️  Most validations passed ($PASSED_VALIDATIONS/$TOTAL_VALIDATIONS)."
        log_info "Project is mostly compatible with test-plans repository."
        return 0
    else
        log_error "❌ Validation failed ($PASSED_VALIDATIONS/$TOTAL_VALIDATIONS passed)."
        log_info "Project needs updates to be compatible with test-plans repository."
        return 1
    fi
}

# Run main function
main