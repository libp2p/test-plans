#!/bin/bash
# Create self-contained test pass snapshot for hole-punch interoperability tests
# Uses common snapshot libraries for code reuse

set -euo pipefail

# Source common snapshot libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$SCRIPT_DIR/../../lib}"
source "$SCRIPT_LIB_DIR/lib-snapshot-creation.sh"
source "$SCRIPT_LIB_DIR/lib-github-snapshots.sh"
source "$SCRIPT_LIB_DIR/lib-snapshot-rerun.sh"
source "$SCRIPT_LIB_DIR/lib-snapshot-images.sh"
source "$SCRIPT_LIB_DIR/lib-inputs-yaml.sh"

# Configuration
TEST_TYPE="hole-punch"
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_PASS_DIR="${TEST_PASS_DIR:-.}"

echo ""
echo "╲ Creating Hole-Punch Test Snapshot"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Step 1: Validate inputs
echo "→ Validating inputs..."
validate_snapshot_inputs "$TEST_PASS_DIR" "$CACHE_DIR" || exit 1

# Step 2: Get test pass name and create snapshot directory
test_pass=$(get_test_pass_name "$TEST_PASS_DIR/results.yaml")
SNAPSHOT_DIR="$CACHE_DIR/test-run/$test_pass"

echo "→ Snapshot: $test_pass"
echo "→ Location: $SNAPSHOT_DIR"

# Step 3: Create directory structure
echo "→ Creating snapshot directory structure..."
create_snapshot_directory "$SNAPSHOT_DIR" || exit 1

# Step 4: Copy configuration and results
echo "→ Copying configuration and results..."
copy_config_files "$SNAPSHOT_DIR" "$TEST_PASS_DIR" "$TEST_TYPE"
copy_impls_directory "$SNAPSHOT_DIR"

# Step 4b: Modify inputs.yaml for snapshot context
echo "→ Modifying inputs.yaml for snapshot context..."
modify_inputs_for_snapshot "$SNAPSHOT_DIR"

# Step 5: Copy scripts
echo "→ Copying scripts..."
copy_all_scripts "$SNAPSHOT_DIR" "$TEST_TYPE"

# Step 6: Copy logs and docker-compose files
echo "→ Copying logs and docker-compose files..."
copy_logs_and_compose "$SNAPSHOT_DIR" "$TEST_PASS_DIR"

# Step 7: Handle GitHub sources (ZIP snapshots and git clones)
echo "→ Handling GitHub sources..."
if ! copy_github_sources_to_snapshot "$SNAPSHOT_DIR" "$CACHE_DIR"; then
    echo "  ⚠ Warning: Some GitHub sources missing from cache"
    echo "  → Snapshot may not be fully self-contained"
fi

# Clean up empty directories
cleanup_empty_source_dirs "$SNAPSHOT_DIR"

# Step 8: Save Docker images (peer, relay, router)
save_docker_images_for_tests "$SNAPSHOT_DIR" "$TEST_TYPE"

# Step 9: Capture original run options (hole-punch specific)
declare -A original_options
original_options[test_select]="${TEST_SELECT:-}"
original_options[test_ignore]="${TEST_IGNORE:-}"
original_options[relay_select]="${RELAY_SELECT:-}"
original_options[relay_ignore]="${RELAY_IGNORE:-}"
original_options[router_select]="${ROUTER_SELECT:-}"
original_options[router_ignore]="${ROUTER_IGNORE:-}"
original_options[workers]="${WORKER_COUNT:-$(nproc 2>/dev/null || echo 4)}"
original_options[debug]="${DEBUG:-false}"

# Step 10: Generate re-run.sh script
echo "→ Generating re-run.sh..."
generate_rerun_script "$SNAPSHOT_DIR" "$TEST_TYPE" "$test_pass" original_options

# Step 11: Create settings.yaml
echo "→ Creating settings.yaml..."
create_settings_yaml "$SNAPSHOT_DIR" "$test_pass" "$TEST_TYPE" "$CACHE_DIR"

# Step 12: Generate README
echo "→ Generating README.md..."
generate_snapshot_readme "$SNAPSHOT_DIR" "$TEST_TYPE" "$test_pass" ""

# Step 13: Validate snapshot is complete
echo "→ Validating snapshot..."
if validate_snapshot_complete "$SNAPSHOT_DIR"; then
    echo "  ✓ Snapshot validation passed"
else
    echo "  ✗ Snapshot validation failed"
    exit 1
fi

# Step 14: Display summary
display_snapshot_summary "$SNAPSHOT_DIR"

echo "✓ Hole-punch snapshot created successfully"
echo ""

exit 0
