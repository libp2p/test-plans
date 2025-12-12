#!/bin/bash
# Create self-contained test pass snapshot for reproducibility
# Similar to hole-punch/scripts/create-snapshot.sh and transport/scripts/create-snapshot.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source "scripts/lib-perf.sh"
source "../scripts/lib-snapshot-images.sh"

CACHE_DIR="${CACHE_DIR:-/srv/cache}"
SNAPSHOT_DIR="${TEST_PASS_DIR:-.}"

if [ ! -f "$SNAPSHOT_DIR/results.yaml" ]; then
    log_error "results.yaml not found in $SNAPSHOT_DIR. Run tests first."
    exit 1
fi

test_pass=$(yq eval '.metadata.testPass' "$SNAPSHOT_DIR/results.yaml")

log_info "Creating snapshot: $test_pass"
echo "  → Location: $SNAPSHOT_DIR"

# Create snapshot subdirectories
log_debug "Creating snapshot structure..."
mkdir -p "$SNAPSHOT_DIR"/{scripts,docker-images}

# Copy essential files
log_info "→ Copying configuration files..."
cp impls.yaml "$SNAPSHOT_DIR/" 2>/dev/null || true

log_info "→ Copying scripts..."
cp scripts/*.sh "$SNAPSHOT_DIR/scripts/" 2>/dev/null || true
cp ../scripts/lib-*.sh "$SNAPSHOT_DIR/scripts/" 2>/dev/null || true

# Save Docker images
log_info "→ Saving Docker images..."

# Get unique implementations from test results
impls=$(yq eval '.tests[].implementation' "$SNAPSHOT_DIR/test-matrix.yaml" | sort -u)

impl_count=$(echo "$impls" | wc -w)
log_debug "  Saving $impl_count implementation images..."

for impl_id in $impls; do
  image_name="perf-${impl_id}"

  if docker_image_exists "$image_name"; then
    log_debug "    → Saving $image_name..."
    docker save "$image_name" | gzip > "$SNAPSHOT_DIR/docker-images/${image_name}.tar.gz" || {
      log_error "    Failed to save $image_name"
    }
    image_size=$(du -h "$SNAPSHOT_DIR/docker-images/${image_name}.tar.gz" | cut -f1)
    log_debug "      ✓ Saved: $image_size"
  else
    log_debug "    ! Image not found: $image_name (skipping)"
  fi
done

log_info "  ✓ Saved $impl_count Docker images"

# Create settings.yaml with test configuration
log_info "→ Creating settings.yaml..."
cat > "$SNAPSHOT_DIR/settings.yaml" <<EOF
testPass: $test_pass
createdAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
platform: $(uname -m)
os: $(uname -s)
cacheDir: $CACHE_DIR

# Test configuration
uploadBytes: $(yq eval '.metadata.uploadBytes' "$SNAPSHOT_DIR/test-matrix.yaml")
downloadBytes: $(yq eval '.metadata.downloadBytes' "$SNAPSHOT_DIR/test-matrix.yaml")
iterations: $(yq eval '.metadata.iterations' "$SNAPSHOT_DIR/test-matrix.yaml")

# Test results summary
summary:
  total: $(yq eval '.summary.total' "$SNAPSHOT_DIR/results.yaml")
  passed: $(yq eval '.summary.passed' "$SNAPSHOT_DIR/results.yaml")
  failed: $(yq eval '.summary.failed' "$SNAPSHOT_DIR/results.yaml")
  partial: $(yq eval '.summary.partial // 0' "$SNAPSHOT_DIR/results.yaml")
EOF

# Create re-run script
log_info "→ Creating re-run.sh..."
cat > "$SNAPSHOT_DIR/re-run.sh" <<'EOF'
#!/bin/bash
# Re-run this test pass snapshot
# This script recreates the exact test run from the snapshot

set -euo pipefail

FORCE_IMAGE_REBUILD=false

# Show help
show_help() {
    cat <<HELP
Re-run Performance Test Snapshot

Usage: $0 [options]

Options:
  --force-image-rebuild    Force rebuilding of Docker images
  --help, -h               Show this help message

Examples:
  $0                        # Re-run using saved Docker images
  $0 --force-image-rebuild  # Rebuild images and re-run

Description:
  This script re-runs a snapshot of a previous performance test. By default,
  it will use pre-saved Docker images from the snapshot. If --force-image-rebuild
  is specified, it will rebuild images from source.

Dependencies:
  bash 4.0+, docker 20.10+, yq 4.0+

Note: Remote server tests require the same remote servers to be accessible.
HELP
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-image-rebuild) FORCE_IMAGE_REBUILD=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; echo ""; show_help; exit 1 ;;
    esac
done

# Change to snapshot directory
cd "$(dirname "$0")"

echo ""
echo "╲ Re-running performance test from snapshot"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Check required files
if [ ! -f impls.yaml ] || [ ! -f test-matrix.yaml ]; then
    echo "✗ Error: Required files missing. This may not be a valid snapshot."
    exit 1
fi

# Read settings
if [ -f settings.yaml ]; then
    echo "╲ Snapshot configuration:"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    grep -v '^#' settings.yaml | grep -v 'cacheDir:' | sed 's/^/  /'
    echo ""
fi

# Load Docker images
if [ "$FORCE_IMAGE_REBUILD" != true ] && [ -d docker-images ]; then
    echo "╲ Loading Docker images from snapshot..."
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

    for image_file in docker-images/*.tar.gz; do
        if [ -f "$image_file" ]; then
            image_name=$(basename "$image_file" .tar.gz)
            echo "  → Loading $image_name..."
            gunzip -c "$image_file" | docker load | sed 's/^/    /'
        fi
    done
    echo "  ✓ All images loaded"
else
    echo "╲ Building Docker images from source..."
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "  ! Image building from snapshot not yet implemented"
    echo "  ! Please load images manually or use original test environment"
    exit 1
fi

echo ""
echo "╲ ✓ Snapshot loaded successfully"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ You can now manually re-run individual tests using the saved configuration"
echo "→ Test matrix: ./test-matrix.yaml"
echo "→ Original results: ./results.yaml"
echo ""
echo "Note: Full re-run script will be implemented in a future phase."
EOF

chmod +x "$SNAPSHOT_DIR/re-run.sh"

# Create README
log_info "→ Creating README.md..."
cat > "$SNAPSHOT_DIR/README.md" <<EOF
# Performance Test Snapshot: $test_pass

This is a self-contained snapshot of a libp2p performance test run.

## Contents

- **impls.yaml** - Implementation definitions used
- **test-matrix.yaml** - Generated test matrix
- **results.yaml** - Test results (structured data)
- **results.md** - Test results (markdown dashboard)
- **results.html** - Test results (HTML dashboard, if generated)
- **settings.yaml** - Snapshot metadata and configuration
- **scripts/** - All test scripts
- **docker-images/** - Saved Docker images for reproducibility
- **logs/** - Test execution logs
- **baseline/** - Baseline test results (ping, iperf)
- **results/** - Individual test result files
- **re-run.sh** - Script to load this snapshot

## Test Summary

\`\`\`yaml
$(yq eval '.summary' "$SNAPSHOT_DIR/results.yaml" || echo "See results.yaml for details")
\`\`\`

## Loading Snapshot

To load this snapshot and explore results:

\`\`\`bash
# Load Docker images
./re-run.sh

# View results
cat results.yaml
cat results.md
\`\`\`

## Using This Snapshot

This snapshot can be used to:
1. **Review results** - All test results, logs, and dashboards are included
2. **Load Docker images** - Recreate exact test environment
3. **Compare runs** - Compare with other snapshots or baseline
4. **Debug failures** - All logs and configurations preserved

## Original Results

See \`results.md\` for the full dashboard from the original run.

---

*Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)*
*Platform: $(uname -m) / $(uname -s)*
EOF

# Calculate snapshot size
log_info "→ Calculating snapshot size..."
snapshot_dir_size=$(du -sh "$SNAPSHOT_DIR" 2>/dev/null | cut -f1 || echo "unknown")
echo "  ✓ Snapshot size: $snapshot_dir_size"

echo ""
echo "╲ ✓ Snapshot created successfully"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ Snapshot: $test_pass"
echo "→ Location: $SNAPSHOT_DIR"
echo "→ Size: $snapshot_dir_size"
echo ""
echo "→ To use this snapshot:"
echo "    cp -r $SNAPSHOT_DIR /path/to/destination"
echo "    cd /path/to/destination/$(basename $SNAPSHOT_DIR)"
echo "    ./re-run.sh"
echo ""
