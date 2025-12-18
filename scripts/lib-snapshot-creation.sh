#!/bin/bash
# Common snapshot creation library
# Shared functions for creating test pass snapshots across all test types

# Validate inputs required for snapshot creation
# Args:
#   $1: test_pass_dir - Directory containing test results
#   $2: cache_dir - Cache directory (usually /srv/cache)
# Returns: 0 if valid, 1 if error
validate_snapshot_inputs() {
    local test_pass_dir="$1"
    local cache_dir="$2"

    # Check test pass directory exists
    if [ ! -d "$test_pass_dir" ]; then
        echo "✗ Error: Test pass directory not found: $test_pass_dir" >&2
        return 1
    fi

    # Check required files exist
    if [ ! -f impls.yaml ]; then
        echo "✗ Error: impls.yaml not found in current directory" >&2
        return 1
    fi

    if [ ! -f "$test_pass_dir/test-matrix.yaml" ]; then
        echo "✗ Error: test-matrix.yaml not found in $test_pass_dir" >&2
        return 1
    fi

    if [ ! -f "$test_pass_dir/results.yaml" ]; then
        echo "✗ Error: results.yaml not found in $test_pass_dir" >&2
        return 1
    fi

    # Check cache directory
    if [ ! -d "$cache_dir" ]; then
        echo "✗ Error: Cache directory not found: $cache_dir" >&2
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

    # If directory exists (created during test execution), just ensure subdirectories
    if [ -d "$snapshot_dir" ]; then
        echo "  → Snapshot directory exists, ensuring subdirectories..."
        mkdir -p "$snapshot_dir"/{logs,docker-compose,docker-images,snapshots,scripts,git-repos}
        echo "  ✓ Snapshot directory structure ready"
        return 0
    fi

    # Directory doesn't exist - create complete structure
    mkdir -p "$snapshot_dir"/{logs,docker-compose,docker-images,snapshots,scripts,git-repos}

    echo "  ✓ Created snapshot directory structure"
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

    # Check if source and destination are the same directory
    local same_dir=false
    if [ "$(cd "$test_pass_dir" 2>/dev/null && pwd)" = "$(cd "$snapshot_dir" 2>/dev/null && pwd)" ]; then
        same_dir=true
    fi

    # Copy impls.yaml (from current directory, always safe)
    if [ ! -f "$snapshot_dir/impls.yaml" ]; then
        cp impls.yaml "$snapshot_dir/" 2>/dev/null || true
    fi

    # Copy impls/ directory if it exists (for local implementations)
    if [ -d impls ] && [ ! -d "$snapshot_dir/impls" ]; then
        cp -r impls "$snapshot_dir/" 2>/dev/null || true
    fi

    # Only copy files if directories are different
    if [ "$same_dir" = false ]; then
        # Copy test matrix
        cp "$test_pass_dir/test-matrix.yaml" "$snapshot_dir/" 2>/dev/null || true

        # Copy results files
        cp "$test_pass_dir/results.yaml" "$snapshot_dir/" 2>/dev/null || true
        cp "$test_pass_dir/results.md" "$snapshot_dir/" 2>/dev/null || true
        cp "$test_pass_dir/results.html" "$snapshot_dir/" 2>/dev/null || true
        cp "$test_pass_dir/LATEST_TEST_RESULTS.md" "$snapshot_dir/" 2>/dev/null || true

        # Copy test-type-specific files
        if [ "$test_type" = "perf" ]; then
            # Copy box plot images
            cp "$test_pass_dir"/*_boxplot.png "$snapshot_dir/" 2>/dev/null || true
        fi

        echo "  ✓ Copied configuration and results files"
    else
        echo "  ✓ Configuration and results already in place (same directory)"
    fi

    return 0
}

# Copy all scripts to snapshot
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: test_type - Type of test (transport, hole-punch, perf)
copy_all_scripts() {
    local snapshot_dir="$1"
    local test_type="$2"

    # Copy test-specific scripts
    cp scripts/*.sh "$snapshot_dir/scripts/" 2>/dev/null || true

    # Copy common scripts from parent directory
    mkdir -p "$snapshot_dir/../scripts"
    cp ../scripts/lib-*.sh "$snapshot_dir/../scripts/" 2>/dev/null || true
    cp ../scripts/*.sh "$snapshot_dir/../scripts/" 2>/dev/null || true

    # Make scripts executable
    chmod +x "$snapshot_dir/scripts/"*.sh 2>/dev/null || true
    chmod +x "$snapshot_dir/../scripts/"*.sh 2>/dev/null || true

    echo "  ✓ Copied all scripts (test-specific + common)"
    return 0
}

# Copy logs and docker-compose files
# Args:
#   $1: snapshot_dir - Target snapshot directory
#   $2: test_pass_dir - Source test pass directory
copy_logs_and_compose() {
    local snapshot_dir="$1"
    local test_pass_dir="$2"

    # Check if source and destination are the same directory
    local same_dir=false
    if [ "$(cd "$test_pass_dir" 2>/dev/null && pwd)" = "$(cd "$snapshot_dir" 2>/dev/null && pwd)" ]; then
        same_dir=true
    fi

    # Only copy if directories are different
    if [ "$same_dir" = false ]; then
        # Copy logs
        if [ -d "$test_pass_dir/logs" ]; then
            cp -r "$test_pass_dir/logs/"* "$snapshot_dir/logs/" 2>/dev/null || true
            local log_count=$(ls -1 "$snapshot_dir/logs/" 2>/dev/null | wc -l)
            echo "  ✓ Copied $log_count log files"
        fi

        # Copy docker-compose files
        if [ -d "$test_pass_dir/docker-compose" ]; then
            cp -r "$test_pass_dir/docker-compose/"* "$snapshot_dir/docker-compose/" 2>/dev/null || true
            local compose_count=$(ls -1 "$snapshot_dir/docker-compose/" 2>/dev/null | wc -l)
            echo "  ✓ Copied $compose_count docker-compose files"
        fi
    else
        # Same directory - files already in place
        local log_count=$(ls -1 "$snapshot_dir/logs/" 2>/dev/null | wc -l)
        local compose_count=$(ls -1 "$snapshot_dir/docker-compose/" 2>/dev/null | wc -l)
        echo "  ✓ Logs and docker-compose already in place ($log_count logs, $compose_count compose files)"
    fi

    return 0
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

    # Extract summary from results.yaml
    local total=$(yq eval '.summary.total' "$snapshot_dir/results.yaml" 2>/dev/null || echo "0")
    local passed=$(yq eval '.summary.passed' "$snapshot_dir/results.yaml" 2>/dev/null || echo "0")
    local failed=$(yq eval '.summary.failed' "$snapshot_dir/results.yaml" 2>/dev/null || echo "0")

    # Extract metadata
    local started_at=$(yq eval '.metadata.startedAt' "$snapshot_dir/results.yaml" 2>/dev/null || echo "")
    local completed_at=$(yq eval '.metadata.completedAt' "$snapshot_dir/results.yaml" 2>/dev/null || echo "")
    local duration=$(yq eval '.metadata.duration' "$snapshot_dir/results.yaml" 2>/dev/null || echo "0")

    cat > "$snapshot_dir/settings.yaml" <<SETTINGS
# Snapshot Settings
testPass: $test_pass
testType: $test_type
createdAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
platform: $(uname -m)
os: $(uname -s)
cacheDir: $cache_dir

# Test execution metadata
startedAt: $started_at
completedAt: $completed_at
duration: $duration

# Summary
summary:
  total: $total
  passed: $passed
  failed: $failed
  passRate: $(awk "BEGIN {if ($total > 0) printf \"%.1f\", ($passed / $total) * 100; else print \"0.0\"}")
SETTINGS

    echo "  ✓ Created settings.yaml"
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

    # Read summary from settings.yaml
    local total=$(yq eval '.summary.total' "$snapshot_dir/settings.yaml" 2>/dev/null || echo "0")
    local passed=$(yq eval '.summary.passed' "$snapshot_dir/settings.yaml" 2>/dev/null || echo "0")
    local failed=$(yq eval '.summary.failed' "$snapshot_dir/settings.yaml" 2>/dev/null || echo "0")
    local pass_rate=$(yq eval '.summary.passRate' "$snapshot_dir/settings.yaml" 2>/dev/null || echo "0.0")

    # Get test type display name
    local test_type_name
    case "$test_type" in
        transport) test_type_name="Transport Interoperability" ;;
        hole-punch) test_type_name="Hole Punch Interoperability" ;;
        perf) test_type_name="Performance Benchmark" ;;
        *) test_type_name="Test" ;;
    esac

    cat > "$snapshot_dir/README.md" <<README
# Test Pass Snapshot: $test_pass

This is a self-contained snapshot of a **$test_type_name** test run.

## Summary

- **Total Tests**: $total
- **Passed**: ✅ $passed
- **Failed**: ❌ $failed
- **Pass Rate**: ${pass_rate}%

## Contents

This snapshot contains everything needed to reproduce the test run:

- **impls.yaml** - Implementation definitions
- **test-matrix.yaml** - Generated test combinations
- **results.yaml** - Structured test results
- **results.md** - Markdown dashboard
- **results.html** - HTML visualization
- **LATEST_TEST_RESULTS.md** - Detailed test results
- **settings.yaml** - Snapshot metadata
- **scripts/** - All test scripts (test-specific)
- **../scripts/** - Common shared libraries
- **logs/** - Test execution logs ($total files)
- **docker-compose/** - Generated compose files
- **docker-images/** - Saved Docker images (compressed)
- **snapshots/** - GitHub source archives (ZIP files)
- **git-repos/** - Git clones with submodules (if applicable)
- **re-run.sh** - Script to reproduce this test run

## Re-running Tests

### Quick Start

\`\`\`bash
# Re-run using cached Docker images
./re-run.sh

# Force rebuild images before running
./re-run.sh --force-image-rebuild

# Re-run with different filters
./re-run.sh --test-select '~rust' --workers 4
\`\`\`

### Available Options

Run \`./re-run.sh --help\` to see all available options.

The re-run script supports the same filtering and configuration options as the
original run_tests.sh script, allowing you to subset or modify the test run.

## Snapshot Details

- **Test Type**: $test_type_name
- **Created**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Platform**: $(uname -m) / $(uname -s)
- **Snapshot Location**: $(pwd)

## Files Structure

\`\`\`
$(basename "$snapshot_dir")/
├── impls.yaml
├── test-matrix.yaml
├── results.yaml
├── results.md
├── results.html
├── LATEST_TEST_RESULTS.md
├── settings.yaml
├── scripts/
│   └── *.sh
├── ../scripts/
│   └── lib-*.sh
├── logs/
├── docker-compose/
├── docker-images/
├── snapshots/          # ZIP archives
├── git-repos/          # Git clones with submodules
├── re-run.sh
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

    echo "  ✓ Created README.md"
    return 0
}

# Calculate and display snapshot summary
# Args:
#   $1: snapshot_dir - Snapshot directory
display_snapshot_summary() {
    local snapshot_dir="$1"

    local snapshot_size=$(du -sh "$snapshot_dir" 2>/dev/null | cut -f1)
    local snapshot_name=$(basename "$snapshot_dir")

    # Count files
    local log_count=$(ls -1 "$snapshot_dir/logs/" 2>/dev/null | wc -l)
    local compose_count=$(ls -1 "$snapshot_dir/docker-compose/" 2>/dev/null | wc -l)
    local image_count=$(ls -1 "$snapshot_dir/docker-images/" 2>/dev/null | wc -l)
    local zip_count=$(ls -1 "$snapshot_dir/snapshots/"*.zip 2>/dev/null | wc -l)
    local git_count=$(ls -d "$snapshot_dir/git-repos/"*/ 2>/dev/null | wc -l)

    echo ""
    echo "╲ Snapshot Summary"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "→ Snapshot: $snapshot_name"
    echo "→ Location: $snapshot_dir"
    echo "→ Size: $snapshot_size"
    echo "→ Logs: $log_count files"
    echo "→ Docker Compose: $compose_count files"
    echo "→ Docker Images: $image_count saved"
    echo "→ ZIP Snapshots: $zip_count files"

    if [ $git_count -gt 0 ]; then
        echo "→ Git Clones: $git_count (with submodules)"
    fi

    echo ""
    echo "To reproduce this test run:"
    echo "  cd $snapshot_dir"
    echo "  ./re-run.sh"
    echo ""

    return 0
}

# Copy impls/ directory if it exists (for local implementations)
# Args:
#   $1: snapshot_dir - Target snapshot directory
copy_impls_directory() {
    local snapshot_dir="$1"

    if [ -d impls ]; then
        cp -r impls "$snapshot_dir/"
        local impl_count=$(find impls -mindepth 1 -maxdepth 1 -type d | wc -l)
        echo "  ✓ Copied impls/ directory ($impl_count local implementations)"
    fi

    return 0
}

# Get test pass name from results
# Args:
#   $1: results_file - Path to results.yaml
# Returns: Test pass name or generates one
get_test_pass_name() {
    local results_file="$1"

    local test_pass=$(yq eval '.metadata.testPass' "$results_file" 2>/dev/null)

    if [ -z "$test_pass" ] || [ "$test_pass" = "null" ]; then
        # Generate name from timestamp
        test_pass="snapshot-$(date +%H%M%S-%d-%m-%Y)"
    fi

    echo "$test_pass"
}

# Validate snapshot was created successfully
# Args:
#   $1: snapshot_dir - Snapshot directory to validate
# Returns: 0 if valid, 1 if errors
validate_snapshot_complete() {
    local snapshot_dir="$1"

    local errors=0

    # Check critical files
    [ ! -f "$snapshot_dir/impls.yaml" ] && echo "✗ Missing: impls.yaml" && errors=$((errors + 1))
    [ ! -f "$snapshot_dir/test-matrix.yaml" ] && echo "✗ Missing: test-matrix.yaml" && errors=$((errors + 1))
    [ ! -f "$snapshot_dir/results.yaml" ] && echo "✗ Missing: results.yaml" && errors=$((errors + 1))
    [ ! -f "$snapshot_dir/settings.yaml" ] && echo "✗ Missing: settings.yaml" && errors=$((errors + 1))
    [ ! -f "$snapshot_dir/README.md" ] && echo "✗ Missing: README.md" && errors=$((errors + 1))
    [ ! -f "$snapshot_dir/re-run.sh" ] && echo "✗ Missing: re-run.sh" && errors=$((errors + 1))
    [ ! -x "$snapshot_dir/re-run.sh" ] && echo "✗ re-run.sh not executable" && errors=$((errors + 1))

    # Check directories
    [ ! -d "$snapshot_dir/scripts" ] && echo "✗ Missing: scripts/" && errors=$((errors + 1))
    [ ! -d "$snapshot_dir/logs" ] && echo "✗ Missing: logs/" && errors=$((errors + 1))

    if [ $errors -gt 0 ]; then
        echo "✗ Snapshot validation failed: $errors errors"
        return 1
    fi

    return 0
}

# Create a compressed archive of the snapshot (optional)
# Args:
#   $1: snapshot_dir - Snapshot directory
#   $2: archive_name - Name for the archive (optional)
# Returns: Path to archive file
create_snapshot_archive() {
    local snapshot_dir="$1"
    local archive_name="${2:-$(basename "$snapshot_dir").tar.gz}"

    local archive_dir=$(dirname "$snapshot_dir")
    local snapshot_name=$(basename "$snapshot_dir")

    cd "$archive_dir"
    tar -czf "$archive_name" "$snapshot_name" 2>/dev/null || {
        echo "✗ Failed to create archive" >&2
        return 1
    }
    cd - >/dev/null

    echo "$archive_dir/$archive_name"
}

# Extract metadata for snapshot from various sources
# Args:
#   $1: test_pass_dir - Test pass directory
# Returns: JSON object with metadata (via stdout)
extract_snapshot_metadata() {
    local test_pass_dir="$1"

    # Try to extract from results.yaml
    if [ -f "$test_pass_dir/results.yaml" ]; then
        yq eval '.metadata' "$test_pass_dir/results.yaml" -o=json 2>/dev/null || echo "{}"
    else
        echo "{}"
    fi
}

# Copy source snapshots/archives with proper structure
# This is a wrapper that can be extended for test-specific needs
# Args:
#   $1: snapshot_dir
#   $2: cache_dir
#   $3: test_type
copy_source_archives() {
    local snapshot_dir="$1"
    local cache_dir="$2"
    local test_type="$3"

    # This function is a placeholder for test-type-specific implementations
    # Each test type may override this with their specific source copying logic
    # For example, transport and hole-punch copy GitHub snapshots,
    # while perf may have different requirements

    echo "  → Source archive copying (test-specific)"
    return 0
}

# Generate a unique snapshot name if not provided
# Args:
#   $1: test_type - Type of test
#   $2: timestamp - Optional timestamp
# Returns: Snapshot directory name
generate_snapshot_name() {
    local test_type="$1"
    local timestamp="${2:-$(date +%H%M%S-%d-%m-%Y)}"

    echo "${test_type}-${timestamp}"
}

# Log a message to snapshot creation log (if logging enabled)
# Args:
#   $1: message - Message to log
#   $2: snapshot_dir - Snapshot directory (optional)
log_snapshot_message() {
    local message="$1"
    local snapshot_dir="${2:-}"

    echo "$message"

    if [ -n "$snapshot_dir" ] && [ -d "$snapshot_dir" ]; then
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) - $message" >> "$snapshot_dir/snapshot-creation.log"
    fi
}
