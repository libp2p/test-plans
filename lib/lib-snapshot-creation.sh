#!/usr/bin/env bash
# Common snapshot creation library
# Shared functions for creating test pass snapshots across all test types

# Source formatting library if not already loaded
if ! type print_message &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_this_script_dir}/lib-output-formatting.sh"
fi

# Create a snapshot
create_snapshot() {
  # Step 1: Validate inputs
  print_message "Validating inputs..."
  validate_snapshot_inputs "${TEST_PASS_DIR}" "${CACHE_DIR}" || return 1

  # Step 2: Get test pass name and create snapshot directory
  test_pass=$(get_test_pass_name "${TEST_PASS_DIR}/results.yaml")
  SNAPSHOT_DIR="${CACHE_DIR}/test-run/${test_pass}"

  print_message "Snapshot: ${test_pass}"
  print_message "Location: ${SNAPSHOT_DIR}"

  # Step 3: Create directory structure
  print_message "Creating snapshot directory structure..."
  create_snapshot_directory "${SNAPSHOT_DIR}" || return 1

  # Step 4: Copy configuration and results
  print_message "Copying configuration and results..."
  copy_config_files "${SNAPSHOT_DIR}" "${TEST_PASS_DIR}" "${TEST_TYPE}"
  copy_images_directory "${SNAPSHOT_DIR}"

  # Step 4b: Modify inputs.yaml for snapshot context
  print_message "Modifying inputs.yaml for snapshot context..."
  modify_inputs_for_snapshot "${SNAPSHOT_DIR}"

  # Step 5: Copy scripts and run.sh
  print_message "Copying scripts..."
  copy_all_scripts "${SNAPSHOT_DIR}" "${TEST_TYPE}"
  copy_run_script "${SNAPSHOT_DIR}" "${TEST_TYPE}"

  # Step 6: Handle GitHub sources (perf typically doesn't use GitHub sources for implementations)
  # But we still support it for completeness
  if [ -d "${CACHE_DIR}/snapshots" ] || [ -d "${CACHE_DIR}/git-repos" ]; then
    print_message "Handling GitHub sources..."
    copy_github_sources_to_snapshot "${SNAPSHOT_DIR}" "${CACHE_DIR}" 2>/dev/null || true
    cleanup_empty_source_dirs "${SNAPSHOT_DIR}"
  fi

  # Step 7: Save Docker images (main + baseline)
  print_message "Saving Docker images..."
  save_docker_images_for_tests "${SNAPSHOT_DIR}" "${TEST_TYPE}"

  # Step 9: Create settings.yaml
  print_message "Creating settings.yaml..."
  create_settings_yaml "${SNAPSHOT_DIR}" "${test_pass}" "${TEST_TYPE}" "${CACHE_DIR}"

  # Step 10: Generate README
  print_message "Generating README.md..."
  generate_snapshot_readme "${SNAPSHOT_DIR}" "${TEST_TYPE}" "${test_pass}" ""

  # Step 11: Validate snapshot is complete
  print_message "Validating snapshot..."
  indent
  if validate_snapshot_complete "${SNAPSHOT_DIR}"; then
    print_success "Snapshot validation passed"
  else
    print_error "Snapshot validation failed"
    unindent
    return 1
  fi
  unindent
  echo ""
  print_success "Snapshot creation complete"
  echo ""

  # Step 13: Display summary
  print_header "Snapshot Summary"
  display_snapshot_summary "${SNAPSHOT_DIR}"
  return 0
}

# Validate inputs required for snapshot creation
# Args:
#   $1: test_pass_dir - Directory containing test results
#   $2: cache_dir - Cache directory (usually /srv/cache)
# Returns: 0 if valid, 1 if error
validate_snapshot_inputs() {
  local test_pass_dir="$1"
  local cache_dir="$2"

  # Check test pass directory exists
  if [ ! -d "${test_pass_dir}" ]; then
    print_error "Error: Test pass directory not found: ${test_pass_dir}"
    return 1
  fi

  # Check required files exist
  if [ ! -f images.yaml ]; then
    print_error "Error: images.yaml not found in current directory"
    return 1
  fi

  if [ ! -f "${test_pass_dir}/test-matrix.yaml" ]; then
    print_error "Error: test-matrix.yaml not found in ${test_pass_dir}"
    return 1
  fi

  if [ ! -f "${test_pass_dir}/results.yaml" ]; then
    print_error "Error: results.yaml not found in ${test_pass_dir}"
    return 1
  fi

  # Check cache directory
  if [ ! -d "${cache_dir}" ]; then
    print_error "Error: Cache directory not found: ${cache_dir}"
    return 1
  fi

  return 0
}

# Create snapshot directory structure
# Args:
#   $1: snapshot_dir - Target snapshot directory
# Returns: 0 on success
# Note: Idempotent - safe to call even if directory exists (from test execution)
create_snapshot_directory() {
  local snapshot_dir="$1"
  indent

  # If directory exists (created during test execution), just ensure subdirectories
  if [ -d "${snapshot_dir}" ]; then
    print_message "Snapshot directory exists, ensuring subdirectories..."
    mkdir -p "${snapshot_dir}"/{logs,docker-compose,docker-images,snapshot,lib,git-repo}
    indent
    print_success "Snapshot directory structure ready"
    unindent
    unindent
    return 0
  fi

  # Directory doesn't exist - create complete structure
  mkdir -p "${snapshot_dir}"/{logs,docker-compose,docker-images,snapshot,lib,git-repo}

  print_success "Created snapshot directory structure"
  unindent
  return 0
}

# Copy configuration files to snapshot
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: test_pass_dir - Source test pass directory
#   $3: test_type - Type of test (transport, hole-punch, perf)
copy_config_files() {
  local snapshot_dir="$1"
  local test_pass_dir="$2"
  local test_type="$3"
  indent

  # Check if source and destination are the same directory
  local same_dir=false
  if [ "$(cd "${test_pass_dir}" 2>/dev/null && pwd)" == "$(cd "${snapshot_dir}" 2>/dev/null && pwd)" ]; then
    same_dir=true
  fi

  # Copy images.yaml (from current directory, always safe)
  if [ ! -f "${snapshot_dir}/images.yaml" ]; then
    cp images.yaml "${snapshot_dir}/" 2>/dev/null || true
  fi

  # Copy impls/ directory if it exists (for local implementations)
  if [ -d impls ] && [ ! -d "${snapshot_dir}/impls" ]; then
    cp -r impls "${snapshot_dir}/" 2>/dev/null || true
  fi

  # Only copy files if directories are different
  if [ "${same_dir}" == "false" ]; then
    # Copy test matrix
    cp "${test_pass_dir}/test-matrix.yaml" "${snapshot_dir}/" 2>/dev/null || true

    # Copy results files
    cp "${test_pass_dir}/results.yaml" "${snapshot_dir}/" 2>/dev/null || true
    cp "${test_pass_dir}/results.md" "${snapshot_dir}/" 2>/dev/null || true
    cp "${test_pass_dir}/results.html" "${snapshot_dir}/" 2>/dev/null || true
    cp "${test_pass_dir}/LATEST_TEST_RESULTS.md" "${snapshot_dir}/" 2>/dev/null || true

    # Copy test-type-specific files
    if [ "${test_type}" == "perf" ]; then
      # Copy box plot images (generated as boxplot-{upload,download,latency}.png)
      cp "${test_pass_dir}"/boxplot-*.png "${snapshot_dir}/" 2>/dev/null || true
    fi

    print_success "Copied configuration and results files"
  else
    print_success "Configuration and results already in place (same directory)"
  fi

  unindent
  return 0
}

# Copy all scripts to snapshot
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: test_type - Type of test (transport, hole-punch, perf)
copy_all_scripts() {
  local snapshot_dir="$1"
  local test_type="$2"
  indent

  # Create lib directory
  mkdir -p "${snapshot_dir}/lib"

  # Copy test-specific scripts to lib/
  cp lib/*.sh "${snapshot_dir}/lib/" 2>/dev/null || true

  # Copy global scripts to SAME lib/ directory
  cp ../lib/*.sh "${snapshot_dir}/lib/" 2>/dev/null || true

  # Copy Redis proxy source if it exists (needed for legacy test support)
  if [ -d "../lib/redis-proxy" ]; then
    cp -r "../lib/redis-proxy" "${snapshot_dir}/lib/"
  fi

  # Make all scripts executable
  chmod +x "${snapshot_dir}/lib/"*.sh 2>/dev/null || true

  print_success "Copied all scripts (test-specific + global to lib/)"
  unindent
  return 0
}

# Copy run.sh script to snapshot
# Args:
#   $1: snapshot_dir - Snapshot directory
#   $2: test_type - Test type (transport, perf, hole-punch)
copy_run_script() {
  local snapshot_dir="$1"
  local test_type="$2"
  indent

  # Copy run.sh from current directory to snapshot
  if [ -f "run.sh" ]; then
    cp run.sh "${snapshot_dir}/run.sh"
    chmod +x "${snapshot_dir}/run.sh"
    print_success "Copied run.sh"
    unindent
    return 0
  else
    print_error "Warning: run.sh not found"
    unindent
    return 1
  fi
}

# Create settings.yaml with snapshot metadata
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: test_pass - Test pass name
#   $3: test_type - Type of test (transport, hole-punch, perf)
#   $4: cache_dir - Cache directory used
create_settings_yaml() {
  local snapshot_dir="$1"
  local test_pass="$2"
  local test_type="$3"
  local cache_dir="$4"
  indent

  # Extract summary from results.yaml
  local total=$(yq eval '.summary.total' "${snapshot_dir}/results.yaml" 2>/dev/null)
  total=${total:-0}
  [ "${total}" = "null" ] && total=0

  local passed=$(yq eval '.summary.passed' "${snapshot_dir}/results.yaml" 2>/dev/null)
  passed=${passed:-0}
  [ "${passed}" = "null" ] && passed=0

  local failed=$(yq eval '.summary.failed' "${snapshot_dir}/results.yaml" 2>/dev/null)
  failed=${failed:-0}
  [ "${failed}" = "null" ] && failed=0

  # Extract metadata
  local started_at=$(yq eval '.metadata.startedAt' "${snapshot_dir}/results.yaml" 2>/dev/null || echo "")
  local completed_at=$(yq eval '.metadata.completedAt' "${snapshot_dir}/results.yaml" 2>/dev/null || echo "")
  local duration=$(yq eval '.metadata.duration' "${snapshot_dir}/results.yaml" 2>/dev/null)
  duration=${duration:-0}
  [ "${duration}" = "null" ] && duration=0

  cat > "${snapshot_dir}/settings.yaml" <<SETTINGS
# Snapshot Settings
testPass: ${test_pass}
testType: ${test_type}
createdAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
platform: $(uname -m)
os: $(uname -s)
cacheDir: ${cache_dir}

# Test execution metadata
startedAt: ${started_at}
completedAt: ${completed_at}
duration: ${duration}

# Summary
summary:
  total: ${total}
  passed: ${passed}
  failed: ${failed}
  passRate: $(if [ "${total}" -gt 0 ]; then echo "scale=1; (${passed} * 100) / ${total}" | bc; else echo "0.0"; fi)
SETTINGS

print_success "Created settings.yaml"
unindent
return 0
}

# Generate README template for snapshot
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: test_type - Type of test
#   $3: test_pass - Test pass name
#   $4: summary_stats - Summary statistics string
generate_snapshot_readme() {
  local snapshot_dir="$1"
  local test_type="$2"
  local test_pass="$3"
  local summary_stats="$4"
  indent

  # Read summary from settings.yaml
  local total=$(yq eval '.summary.total' "${snapshot_dir}/settings.yaml" 2>/dev/null || echo "0")
  local passed=$(yq eval '.summary.passed' "${snapshot_dir}/settings.yaml" 2>/dev/null || echo "0")
  local failed=$(yq eval '.summary.failed' "${snapshot_dir}/settings.yaml" 2>/dev/null || echo "0")
  local pass_rate=$(yq eval '.summary.passRate' "${snapshot_dir}/settings.yaml" 2>/dev/null || echo "0.0")

  # Get test type display name
  local test_type_name
  case "${test_type}" in
    transport) test_type_name="Transport Interoperability" ;;
    hole-punch) test_type_name="Hole Punch Interoperability" ;;
    perf) test_type_name="Performance Benchmark" ;;
    *) test_type_name="Test" ;;
  esac

  cat > "${snapshot_dir}/README.md" <<README
# Test Pass Snapshot: ${test_pass}

This is a self-contained snapshot of a **${test_type_name}** test run.

## Summary

- **Total Tests**: ${total}
- **Passed**: ✅ ${passed}
- **Failed**: ❌ ${failed}
- **Pass Rate**: ${pass_rate}%

## Contents

This snapshot contains everything needed to reproduce the test run:

- **images.yaml** - Implementation definitions
- **test-matrix.yaml** - Generated test combinations
- **results.yaml** - Structured test results
- **results.md** - Markdown dashboard
- **results.html** - HTML visualization
- **LATEST_TEST_RESULTS.md** - Detailed test results
- **settings.yaml** - Snapshot metadata
- **lib/** - Test-specific scripts
- **../lib/** - Common shared libraries
- **logs/** - Test execution logs (${total} files)
- **docker-compose/** - Generated compose files
- **docker-images/** - Saved Docker images (compressed)
- **snapshot/** - GitHub source archives (ZIP files)
- **git-repo/** - Git clones with submodules (if applicable)

## Re-running Tests

### Quick Start

\`\`\`bash
# Re-run using cached Docker images
./run.sh

# Force rebuild images before running
./run.sh --force-image-rebuild

# Re-run with different filters
./run.sh --test-select '~rust' --workers 4
\`\`\`

### Available Options

Run \`./run.sh --help\` to see all available options.

The run script supports the same filtering and configuration options as the
original run_tests.sh script, allowing you to subset or modify the test run.

## Snapshot Details

- **Test Type**: ${test_type_name}
- **Created**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Platform**: $(uname -m) / $(uname -s)
- **Snapshot Location**: $(pwd)

## Files Structure

\`\`\`
$(basename "${snapshot_dir}")/
├── images.yaml
├── test-matrix.yaml
├── results.yaml
├── results.md
├── results.html
├── LATEST_TEST_RESULTS.md
├── settings.yaml
├── lib/
│   ├── *.sh
│   └── lib-*.sh
├── logs/
├── docker-compose/
├── docker-images/
├── snapshots/          # ZIP archives
├── git-repos/          # Git clones with submodules
├── run.sh
└── README.md (this file)
\`\`\`

## Requirements

To re-run this snapshot, you need:
- bash 4.0+
- docker 20.10+
- yq 4.0+
- wget, unzip
- git (if implementations use submodules)

## Notes

- This snapshot is fully self-contained and can be moved to any system
- GitHub source code is included (both ZIP and git clones as needed)
- Docker images are saved and can be loaded without rebuilding
- All scripts and configuration are captured at the time of the test run

---

*Snapshot created: $(date -u +%Y-%m-%dT%H:%M:%SZ)*
README

print_success "Created README.md"
unindent
return 0
}

# Calculate and display snapshot summary
# Args:
#   $1: snapshot_dir - Snapshot directory
display_snapshot_summary() {
  local snapshot_dir="$1"

  local snapshot_size=$(du -sh "${snapshot_dir}" 2>/dev/null | cut -f1)
  local snapshot_name=$(basename "${snapshot_dir}")

  # Count files
  local log_count=$(ls -1 "${snapshot_dir}/logs/" 2>/dev/null | wc -l)
  local compose_count=$(ls -1 "${snapshot_dir}/docker-compose/" 2>/dev/null | wc -l)
  local image_count=$(ls -1 "${snapshot_dir}/docker-images/" 2>/dev/null | wc -l)
  local zip_count=$(ls -1 "${snapshot_dir}/snapshot/"*.zip 2>/dev/null | wc -l)
  local git_count=$(ls -d "${snapshot_dir}/git-repo/"*/ 2>/dev/null | wc -l)

  print_message "Snapshot: ${snapshot_name}"
  print_message "Location: ${snapshot_dir}"
  print_message "Size: ${snapshot_size}"
  print_message "Logs: ${log_count} files"
  print_message "Docker Compose: ${compose_count} files"
  print_message "Docker Images: ${image_count} saved"
  print_message "ZIP Snapshots: ${zip_count} files"

  if [ ${git_count} -gt 0 ]; then
    print_message "Git Clones: ${git_count} (with submodules)"
  fi

  echo ""
  print_message "To reproduce this test run:"
  indent
  print_message "cd ${snapshot_dir}"
  print_message "./run.sh"
  unindent
  echo ""

  return 0
}

# Copy images/ directory if it exists (for local implementations)
# Args:
#   $1: snapshot_dir - Target snapshot directory
copy_images_directory() {
  local snapshot_dir="$1"
  indent

  if [ -d images ]; then
    cp -r images "${snapshot_dir}/"
    local impl_count=$(find images -mindepth 1 -maxdepth 1 -type d | wc -l)
    print_success "Copied images/ directory (${impl_count} local implementations)"
  fi

  unindent
  return 0
}

# Get test pass name from results
# Args:
#   $1: results_file - Path to results.yaml
# Returns: Test pass name or generates one
get_test_pass_name() {
  local results_file="$1"

  local test_pass=$(yq eval '.metadata.testPass' "${results_file}" 2>/dev/null)

  if [ -z "${test_pass}" ] || [ "${test_pass}" == "null" ]; then
    # Generate name from timestamp
    test_pass="snapshot-$(date +%H%M%S-%d-%m-%Y)"
  fi

  echo "${test_pass}"
}

# Validate snapshot was created successfully
# Args:
#   $1: snapshot_dir - Snapshot directory to validate
# Returns: 0 if valid, 1 if errors
validate_snapshot_complete() {
  local snapshot_dir="$1"
  indent

  local errors=0

  # Check critical files
  [ ! -f "${snapshot_dir}/images.yaml" ] && print_error "Missing: images.yaml" && errors=$((${errors} + 1))
  [ ! -f "${snapshot_dir}/test-matrix.yaml" ] && print_error "Missing: test-matrix.yaml" && errors=$((${errors} + 1))
  [ ! -f "${snapshot_dir}/results.yaml" ] && print_error "Missing: results.yaml" && errors=$((${errors} + 1))
  [ ! -f "${snapshot_dir}/settings.yaml" ] && print_error "Missing: settings.yaml" && errors=$((${errors} + 1))
  [ ! -f "${snapshot_dir}/README.md" ] && print_error "Missing: README.md" && errors=$((${errors} + 1))
  [ ! -f "${snapshot_dir}/run.sh" ] && print_error "Missing: run.sh" && errors=$((${errors} + 1))
  [ ! -x "${snapshot_dir}/run.sh" ] && print_error "run.sh not executable" && errors=$((${errors} + 1))

  # Check directories
  [ ! -d "${snapshot_dir}/lib" ] && print_error "Missing: lib/" && errors=$((${errors} + 1))
  [ ! -d "${snapshot_dir}/logs" ] && print_error "Missing: logs/" && errors=$((${errors} + 1))

  if [ ${errors} -gt 0 ]; then
    print_error "Snapshot validation: ${errors} errors"
    unindent
    return 1
  fi

  unindent
  return 0
}
