#!/bin/bash
# Create self-contained test pass snapshot for performance benchmark tests
# Uses common snapshot libraries for code reuse

set -euo pipefail

# Source common snapshot libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source "$SCRIPT_LIB_DIR/lib-snapshot-creation.sh"
source "$SCRIPT_LIB_DIR/lib-github-snapshots.sh"
source "$SCRIPT_LIB_DIR/lib-snapshot-images.sh"
source "$SCRIPT_LIB_DIR/lib-inputs-yaml.sh"
source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"
source "lib/lib-perf.sh"

# Configuration
TEST_TYPE="perf"
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_PASS_DIR="${TEST_PASS_DIR:-.}"

echo ""
print_header "Creating Performance Test Snapshot"

# Step 1: Validate inputs
echo "  → Validating inputs..."
validate_snapshot_inputs "$TEST_PASS_DIR" "$CACHE_DIR" || exit 1

# Step 2: Get test pass name and create snapshot directory
test_pass=$(get_test_pass_name "$TEST_PASS_DIR/results.yaml")
SNAPSHOT_DIR="$CACHE_DIR/test-run/$test_pass"

echo "  → Snapshot: $test_pass"
echo "  → Location: $SNAPSHOT_DIR"

# Step 3: Create directory structure
echo "  → Creating snapshot directory structure..."
create_snapshot_directory "$SNAPSHOT_DIR" || exit 1

# Step 4: Copy configuration and results
echo "  → Copying configuration and results..."
copy_config_files "$SNAPSHOT_DIR" "$TEST_PASS_DIR" "$TEST_TYPE"
copy_impls_directory "$SNAPSHOT_DIR"

# Step 4b: Modify inputs.yaml for snapshot context
echo "  → Modifying inputs.yaml for snapshot context..."
modify_inputs_for_snapshot "$SNAPSHOT_DIR"

# Step 5: Copy scripts and run.sh
echo "  → Copying scripts..."
copy_all_scripts "$SNAPSHOT_DIR" "$TEST_TYPE"
copy_run_script "$SNAPSHOT_DIR" "$TEST_TYPE"

# Note: Perf tests create logs during re-run, not during initial run
# So we don't copy logs here - they'll be generated during re-run

# Step 6: Handle GitHub sources (perf typically doesn't use GitHub sources for implementations)
# But we still support it for completeness
if [ -d "$CACHE_DIR/snapshots" ] || [ -d "$CACHE_DIR/git-repos" ]; then
    echo "  → Handling GitHub sources..."
    copy_github_sources_to_snapshot "$SNAPSHOT_DIR" "$CACHE_DIR" 2>/dev/null || true
    cleanup_empty_source_dirs "$SNAPSHOT_DIR"
fi

# Step 7: Save Docker images (main + baseline)
save_docker_images_for_tests "$SNAPSHOT_DIR" "$TEST_TYPE"

# Step 8: run.sh and inputs.yaml are already copied/configured
# No need to generate re-run.sh - users will run ./run.sh which reads inputs.yaml

# Step 9: Create settings.yaml
echo "  → Creating settings.yaml..."
create_settings_yaml "$SNAPSHOT_DIR" "$test_pass" "$TEST_TYPE" "$CACHE_DIR"

# Step 10: Generate README
echo "  → Generating README.md..."
generate_snapshot_readme "$SNAPSHOT_DIR" "$TEST_TYPE" "$test_pass" ""

# Step 11: Validate snapshot is complete
echo "  → Validating snapshot..."
if validate_snapshot_complete "$SNAPSHOT_DIR"; then
    echo "    ✓ Snapshot validation passed"
else
    echo "    ✗ Snapshot validation failed"
    exit 1
fi

# Step 13: Display summary
display_snapshot_summary "$SNAPSHOT_DIR"

echo "  ✓ Performance test snapshot created successfully"
echo ""

exit 0
