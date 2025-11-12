#!/bin/bash
# Create self-contained test pass snapshot for reproducibility

set -euo pipefail

CACHE_DIR="${CACHE_DIR:-/srv/cache}"

if [ ! -f results.yaml ]; then
    echo "Error: results.yaml not found. Run tests first."
    exit 1
fi

echo "Creating test pass snapshot..."

# Extract test pass name from results
test_pass=$(yq eval '.metadata.testPass' results.yaml)
snapshot_name="${test_pass}"
snapshot_dir="$CACHE_DIR/test-passes/$snapshot_name"

# Create snapshot directory structure
mkdir -p "$snapshot_dir"/{scripts,snapshots,docker-compose,logs}

echo "Snapshot: $snapshot_name"
echo "Location: $snapshot_dir"
echo ""

# Copy essential files
echo "→ Copying configuration files..."
cp impls.yaml "$snapshot_dir/"
cp test-selection.yaml "$snapshot_dir/"
cp -r impls "$snapshot_dir/" 2>/dev/null || true

echo "→ Copying test results..."
cp results.yaml "$snapshot_dir/"
cp results.md "$snapshot_dir/" 2>/dev/null || true
cp test-matrix.yaml "$snapshot_dir/" 2>/dev/null || true

echo "→ Copying scripts..."
cp scripts/*.sh "$snapshot_dir/scripts/"

echo "→ Copying logs..."
cp logs/*.log "$snapshot_dir/logs/" 2>/dev/null || true

echo "→ Copying docker-compose files..."
cp docker-compose-*.yaml "$snapshot_dir/docker-compose/" 2>/dev/null || true

# Copy snapshots used in this test run
echo "→ Copying source snapshots..."
test_count=$(yq eval '.tests | length' results.yaml)

for ((i=0; i<test_count; i++)); do
    dialer_snapshot=$(yq eval ".tests[$i].dialerSnapshot" test-matrix.yaml 2>/dev/null || echo "")
    listener_snapshot=$(yq eval ".tests[$i].listenerSnapshot" test-matrix.yaml 2>/dev/null || echo "")

    if [ -n "$dialer_snapshot" ] && [ -f "$CACHE_DIR/$dialer_snapshot" ]; then
        snapshot_basename=$(basename "$dialer_snapshot")
        if [ ! -f "$snapshot_dir/snapshots/$snapshot_basename" ]; then
            cp "$CACHE_DIR/$dialer_snapshot" "$snapshot_dir/snapshots/"
            # Copy metadata if exists
            [ -f "$CACHE_DIR/$dialer_snapshot.metadata" ] && \
                cp "$CACHE_DIR/$dialer_snapshot.metadata" "$snapshot_dir/snapshots/"
        fi
    fi

    if [ -n "$listener_snapshot" ] && [ -f "$CACHE_DIR/$listener_snapshot" ]; then
        snapshot_basename=$(basename "$listener_snapshot")
        if [ ! -f "$snapshot_dir/snapshots/$snapshot_basename" ]; then
            cp "$CACHE_DIR/$listener_snapshot" "$snapshot_dir/snapshots/"
            # Copy metadata if exists
            [ -f "$CACHE_DIR/$listener_snapshot.metadata" ] && \
                cp "$CACHE_DIR/$listener_snapshot.metadata" "$snapshot_dir/snapshots/"
        fi
    fi
done

# Create settings.yaml with test configuration
echo "→ Creating settings.yaml..."
cat > "$snapshot_dir/settings.yaml" <<EOF
testPass: $test_pass
createdAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
platform: $(uname -m)
os: $(uname -s)
cacheDir: $CACHE_DIR

# Original test configuration
testFilter: $(yq eval '.metadata.filter' test-matrix.yaml)
testIgnore: $(yq eval '.metadata.ignore' test-matrix.yaml)

# Test results summary
summary:
  total: $(yq eval '.summary.total' results.yaml)
  passed: $(yq eval '.summary.passed' results.yaml)
  failed: $(yq eval '.summary.failed' results.yaml)
EOF

# Create re-run script
echo "→ Creating re-run.sh..."
cat > "$snapshot_dir/re-run.sh" <<'EOF'
#!/bin/bash
# Re-run this test pass snapshot
# This script recreates the exact test run from the snapshot

set -euo pipefail

echo "Re-running test pass from snapshot..."
echo ""

# Change to snapshot directory
cd "$(dirname "$0")"

# Check if required files exist
if [ ! -f impls.yaml ] || [ ! -f test-matrix.yaml ]; then
    echo "Error: Required files missing. This may not be a valid snapshot."
    exit 1
fi

# Read settings
if [ -f settings.yaml ]; then
    echo "Snapshot configuration:"
    cat settings.yaml
    echo ""
fi

# Set cache dir to local snapshots directory
export CACHE_DIR="$(pwd)"

echo "This snapshot contains all source code and configurations."
echo "Re-running will use the cached artifacts in this directory."
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Build images from cached snapshots
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building images from cached snapshots..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/build-images.sh

# Start services
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting global services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/start-global-services.sh

# Cleanup on exit
cleanup() {
    echo ""
    echo "Stopping services..."
    bash scripts/stop-global-services.sh
}
trap cleanup EXIT

# Re-run tests
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Re-running tests..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_count=$(yq eval '.tests | length' test-matrix.yaml)
echo "Total tests: $test_count"
echo ""

for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".tests[$i].name" test-matrix.yaml)
    dialer=$(yq eval ".tests[$i].dialer" test-matrix.yaml)
    listener=$(yq eval ".tests[$i].listener" test-matrix.yaml)
    transport=$(yq eval ".tests[$i].transport" test-matrix.yaml)

    echo "[$((i + 1))/$test_count] $name"
    bash scripts/run-single-test.sh "$name" "$dialer" "$listener" "$transport" || true
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Re-run complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EOF

chmod +x "$snapshot_dir/re-run.sh"

# Create README
echo "→ Creating README.md..."
cat > "$snapshot_dir/README.md" <<EOF
# Test Pass Snapshot: $test_pass

This is a self-contained snapshot of a hole punch interoperability test run.

## Contents

- **impls.yaml** - Implementation definitions used
- **test-matrix.yaml** - Generated test matrix
- **results.yaml** - Test results (structured data)
- **results.md** - Test results (markdown dashboard)
- **settings.yaml** - Snapshot metadata and configuration
- **scripts/** - All test scripts
- **snapshots/** - Source code snapshots (GitHub archives)
- **docker-compose/** - Generated docker-compose files
- **logs/** - Test execution logs
- **re-run.sh** - Script to reproduce this test run

## Re-running Tests

To reproduce this test run on any machine with bash, docker, git, yq, wget, and unzip:

\`\`\`bash
./re-run.sh
\`\`\`

This will:
1. Build Docker images from cached source snapshots
2. Start global services (Redis, Relay)
3. Re-run all tests with the same configuration
4. Generate new results

## Test Summary

$(cat "$snapshot_dir/results.yaml" | grep -A 10 "^summary:" || echo "See results.yaml for details")

## Original Results

See \`results.md\` for the full test dashboard from the original run.

---

*Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)*
EOF

# Create archive
echo ""
echo "→ Creating archive..."
cd "$CACHE_DIR/test-passes"
tar -czf "${snapshot_name}.tar.gz" "$snapshot_name"

snapshot_size=$(du -h "${snapshot_name}.tar.gz" | cut -f1)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Snapshot created successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Snapshot: $snapshot_name"
echo "Location: $snapshot_dir"
echo "Archive: ${snapshot_name}.tar.gz ($snapshot_size)"
echo ""
echo "To extract and re-run:"
echo "  tar -xzf ${snapshot_name}.tar.gz"
echo "  cd $snapshot_name"
echo "  ./re-run.sh"
