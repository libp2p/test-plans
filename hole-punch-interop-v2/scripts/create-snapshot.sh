#!/bin/bash
# Create self-contained test pass snapshot for reproducibility

set -euo pipefail

CACHE_DIR="${CACHE_DIR:-/srv/cache}"

# Use TEST_PASS_DIR if set, otherwise use current directory
SNAPSHOT_DIR="${TEST_PASS_DIR:-.}"

if [ ! -f "$SNAPSHOT_DIR/results.yaml" ]; then
    echo "✗ Error: results.yaml not found in $SNAPSHOT_DIR. Run tests first."
    exit 1
fi

# Extract test pass name from results
test_pass=$(yq eval '.metadata.testPass' "$SNAPSHOT_DIR/results.yaml")

echo "→ Snapshot: $test_pass"
echo "→ Location: $SNAPSHOT_DIR"

# Create snapshot subdirectories if they don't exist
mkdir -p "$SNAPSHOT_DIR"/{scripts,snapshots,docker-compose,logs,docker-images}

# Copy essential files (only if they don't already exist in snapshot dir)
echo "→ Copying configuration files..."
cp impls.yaml "$SNAPSHOT_DIR/" 2>/dev/null || true
cp -r impls "$SNAPSHOT_DIR/" 2>/dev/null || true

echo "→ Copying scripts..."
cp scripts/*.sh "$SNAPSHOT_DIR/scripts/" 2>/dev/null || true

# Validate and copy snapshots used in this test run
echo "→ Validating and copying source snapshots..."
test_count=$(yq eval '.tests | length' "$SNAPSHOT_DIR/results.yaml")

# First pass: collect all unique snapshots and validate they exist
declare -A unique_snapshots
missing_count=0

for ((i=0; i<test_count; i++)); do
    dialer_snapshot=$(yq eval ".tests[$i].dialerSnapshot" "$SNAPSHOT_DIR/test-matrix.yaml" 2>/dev/null || echo "")
    listener_snapshot=$(yq eval ".tests[$i].listenerSnapshot" "$SNAPSHOT_DIR/test-matrix.yaml" 2>/dev/null || echo "")

    if [ -n "$dialer_snapshot" ] && [ "$dialer_snapshot" != "null" ]; then
        unique_snapshots["$dialer_snapshot"]=1
    fi

    if [ -n "$listener_snapshot" ] && [ "$listener_snapshot" != "null" ]; then
        unique_snapshots["$listener_snapshot"]=1
    fi
done

# Check and download missing snapshots
for snapshot_path in "${!unique_snapshots[@]}"; do
    if [ ! -f "$CACHE_DIR/$snapshot_path" ]; then
        snapshot_basename=$(basename "$snapshot_path")
        commit="${snapshot_basename%.zip}"

        # Find the repo for this commit
        repo=$(yq eval ".implementations[] | select(.source.commit == \"$commit\") | .source.repo" impls.yaml | head -1)

        if [ -n "$repo" ]; then
            echo "  → Downloading missing snapshot: $snapshot_basename..."
            repo_url="https://github.com/$repo/archive/$commit.zip"
            mkdir -p "$CACHE_DIR/snapshots"
            wget -q -O "$CACHE_DIR/$snapshot_path" "$repo_url" || {
                echo "  ✗ Failed to download $snapshot_basename"
                exit 1
            }
            echo "    ✓ Downloaded to cache"
        else
            echo "  ✗ Could not find repo for commit $commit"
            exit 1
        fi
    fi
done

# Second pass: copy all snapshots to snapshot directory
for snapshot_path in "${!unique_snapshots[@]}"; do
    snapshot_basename=$(basename "$snapshot_path")
    if [ ! -f "$SNAPSHOT_DIR/snapshots/$snapshot_basename" ]; then
        cp "$CACHE_DIR/$snapshot_path" "$SNAPSHOT_DIR/snapshots/"
        # Copy metadata if exists
        [ -f "$CACHE_DIR/$snapshot_path.metadata" ] && \
            cp "$CACHE_DIR/$snapshot_path.metadata" "$SNAPSHOT_DIR/snapshots/"
    fi
done

echo "  ✓ All snapshots validated and copied"

# Save Docker images
echo "→ Saving Docker images..."

# Get unique implementations from test matrix
yq eval '.tests[].dialer' "$SNAPSHOT_DIR/test-matrix.yaml" | sort -u > /tmp/snapshot-impls.txt
yq eval '.tests[].listener' "$SNAPSHOT_DIR/test-matrix.yaml" | sort -u >> /tmp/snapshot-impls.txt
sort -u /tmp/snapshot-impls.txt -o /tmp/snapshot-impls.txt

while read -r impl_id; do
    if docker image inspect "$impl_id" &> /dev/null; then
        image_file="$SNAPSHOT_DIR/docker-images/${impl_id}.tar.gz"
        if [ ! -f "$image_file" ]; then
            echo "  → Saving: $impl_id"
            docker save "$impl_id" | gzip > "$image_file"
        fi
    else
        echo "  ⚠ Image not found: $impl_id (will need to rebuild on re-run)"
    fi
done < /tmp/snapshot-impls.txt

rm /tmp/snapshot-impls.txt
echo "  ✓ Docker images saved"

# Create settings.yaml with test configuration
echo "→ Creating settings.yaml..."
cat > "$SNAPSHOT_DIR/settings.yaml" <<EOF
testPass: $test_pass
createdAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
platform: $(uname -m)
os: $(uname -s)
cacheDir: $CACHE_DIR

# Original test configuration
testSelect: $(yq eval '.metadata.select' "$SNAPSHOT_DIR/test-matrix.yaml")
testIgnore: $(yq eval '.metadata.ignore' "$SNAPSHOT_DIR/test-matrix.yaml")

# Test results summary
summary:
  total: $(yq eval '.summary.total' "$SNAPSHOT_DIR/results.yaml")
  passed: $(yq eval '.summary.passed' "$SNAPSHOT_DIR/results.yaml")
  failed: $(yq eval '.summary.failed' "$SNAPSHOT_DIR/results.yaml")
EOF

# Create re-run script
echo "→ Creating re-run.sh..."
cat > "$SNAPSHOT_DIR/re-run.sh" <<'EOF'
#!/bin/bash
# Re-run this test pass snapshot
# This script recreates the exact test run from the snapshot

set -euo pipefail

FORCE_REBUILD=false

# Show help
show_help() {
    cat <<HELP
Re-run Test Pass Snapshot

Usage: $0 [options]

Options:
  --force-rebuild    Force rebuilding of all docker images before re-running
  --help, -h         Show this help message

Examples:
  $0                    # Re-run tests using cached Docker images
  $0 --force-rebuild    # Rebuild images and re-run tests

Description:
  This script re-runs a snapshot of a previous test pass. By default, it will
  use pre-saved Docker images from the snapshot. If the images are not present
  or --force-rebuild is specified, it will rebuild only the images needed for
  the tests in this snapshot based on impls.yaml and test-matrix.yaml.

Dependencies:
  bash 4.0+, docker 20.10+, yq 4.0+, wget, unzip
HELP
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-rebuild) FORCE_REBUILD=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; echo ""; show_help; exit 1 ;;
    esac
done

# Change to snapshot directory
cd "$(dirname "$0")"

echo ""
echo "                        ╔╦╦╗  ╔═╗"
echo "▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╠╣╚╦═╬╝╠═╗ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁"
echo "═══════════════════════ ║║║║║║║╔╣║║ ════════════════════════"
echo "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚╩╩═╣╔╩═╣╔╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "                            ╚╝  ╚╝"
echo ""

echo "╲ Re-running test pass from snapshot"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Check if required files exist
if [ ! -f impls.yaml ] || [ ! -f test-matrix.yaml ]; then
    echo "✗ Error: Required files missing. This may not be a valid snapshot."
    exit 1
fi

# Read settings
if [ -f settings.yaml ]; then
    echo "╲ Snapshot configuration:"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    grep -v '^#' settings.yaml | grep -v 'cacheDir:' | sed 's/^/  /'
    echo ""
fi

# Set cache dir to local directory
export CACHE_DIR="$(pwd)"

# Create re-run subdirectory
RERUN_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RERUN_DIR="re-runs/$RERUN_TIMESTAMP"
mkdir -p "$RERUN_DIR"/{logs,docker-compose}

# Copy test-matrix.yaml to re-run directory so scripts can find it
cp test-matrix.yaml "$RERUN_DIR/"

export TEST_PASS_DIR="$RERUN_DIR"

echo "This snapshot contains all source code and configurations."
echo "Re-run results will be saved to: re-runs/$RERUN_TIMESTAMP"
echo "Re-running will use the cached artifacts in this directory."
echo ""
read -p "Continue? (Y/n) " -n 1 response
response=${response:-Y} # Default to Y if user just presses enter
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Test execution cancelled."
    exit 0
fi

# Validate GitHub snapshots are present
echo ""
echo "╲ Validating GitHub snapshots..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Check each snapshot referenced in test-matrix.yaml
test_count=$(yq eval '.tests | length' test-matrix.yaml)
missing_snapshots=()

for ((i=0; i<test_count; i++)); do
    dialer_snapshot=$(yq eval ".tests[$i].dialerSnapshot" test-matrix.yaml 2>/dev/null || echo "")
    listener_snapshot=$(yq eval ".tests[$i].listenerSnapshot" test-matrix.yaml 2>/dev/null || echo "")

    # Check dialer snapshot (should be in local snapshots/ directory)
    if [ -n "$dialer_snapshot" ] && [ "$dialer_snapshot" != "null" ]; then
        snapshot_name=$(basename "$dialer_snapshot")
        if [ ! -f "snapshots/$snapshot_name" ]; then
            missing_snapshots+=("$snapshot_name")
        fi
    fi

    # Check listener snapshot (should be in local snapshots/ directory)
    if [ -n "$listener_snapshot" ] && [ "$listener_snapshot" != "null" ]; then
        snapshot_name=$(basename "$listener_snapshot")
        if [ ! -f "snapshots/$snapshot_name" ]; then
            missing_snapshots+=("$snapshot_name")
        fi
    fi
done

# Verify all snapshots are present
if [ ${#missing_snapshots[@]} -gt 0 ]; then
    echo "  ✗ Missing ${#missing_snapshots[@]} snapshot(s):"
    for snapshot_file in "${missing_snapshots[@]}"; do
        echo "    - $snapshot_file"
    done
    echo ""
    echo "  This snapshot appears to be incomplete or corrupted."
    echo "  Please re-create the snapshot from the original test run."
    exit 1
else
    echo "  ✓ All snapshots present"
fi

# Load or build Docker images
echo ""
echo "╲ Loading/Building Docker images..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Get unique implementations from test matrix (dialer + listener)
REQUIRED_IMPLS=$(mktemp)
yq eval '.tests[].dialer' test-matrix.yaml | sort -u > "$REQUIRED_IMPLS"
yq eval '.tests[].listener' test-matrix.yaml | sort -u >> "$REQUIRED_IMPLS"
sort -u "$REQUIRED_IMPLS" -o "$REQUIRED_IMPLS"

# Also add base images for any browser-type implementations
REQUIRED_IMPLS_WITH_DEPS=$(mktemp)
cp "$REQUIRED_IMPLS" "$REQUIRED_IMPLS_WITH_DEPS"

while IFS= read -r impl_id; do
    # Check if this is a browser-type implementation
    source_type=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .source.type" impls.yaml)
    if [ "$source_type" = "browser" ]; then
        # Add its base image as a dependency
        base_image=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .source.baseImage" impls.yaml)
        echo "$base_image" >> "$REQUIRED_IMPLS_WITH_DEPS"
    fi
done < "$REQUIRED_IMPLS"

# Sort and deduplicate
sort -u "$REQUIRED_IMPLS_WITH_DEPS" -o "$REQUIRED_IMPLS_WITH_DEPS"

IMPL_COUNT=$(wc -l < "$REQUIRED_IMPLS_WITH_DEPS")

if [ "$FORCE_REBUILD" = true ]; then
    echo "  → Force rebuild requested, building $IMPL_COUNT required implementations..."
    IMPL_FILTER=$(cat "$REQUIRED_IMPLS_WITH_DEPS" | paste -sd'|' -)
    bash scripts/build-images.sh "$IMPL_FILTER" "true"
    echo "  ✓ All images rebuilt"
elif [ -d docker-images ] && [ "$(ls -A docker-images 2>/dev/null)" ]; then
    echo "  → Loading $IMPL_COUNT images from snapshot..."
    for image_file in docker-images/*.tar.gz; do
        if [ -f "$image_file" ]; then
            image_name=$(basename "$image_file" .tar.gz)
            gunzip -c "$image_file" | docker load | sed 's/^/    /'
        fi
    done
    echo "  ✓ All images loaded"
else
    echo "  ! No docker-images directory found, building $IMPL_COUNT required implementations..."
    IMPL_FILTER=$(cat "$REQUIRED_IMPLS_WITH_DEPS" | paste -sd'|' -)
    bash scripts/build-images.sh "$IMPL_FILTER" "false"
    echo "  ✓ All images built"
fi

rm -f "$REQUIRED_IMPLS" "$REQUIRED_IMPLS_WITH_DEPS"

# Start global services
echo ""
echo "╲ Starting global services..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
bash scripts/start-global-services.sh

WORKER_COUNT=$(nproc 2>/dev/null || echo 4)

# Re-run tests in parallel
echo ""
echo "╲ Re-running tests... ($WORKER_COUNT workers)"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

test_count=$(yq eval '.tests | length' test-matrix.yaml)

# Initialize results
> "$RERUN_DIR/results.yaml.tmp"
export test_count

# Track start time
RERUN_START_TIME=$(date +%s)

# Run test function
run_test() {
    local index=$1
    local name=$(yq eval ".tests[$index].name" "$RERUN_DIR/test-matrix.yaml")
    local dialer=$(yq eval ".tests[$index].dialer" "$RERUN_DIR/test-matrix.yaml")
    local listener=$(yq eval ".tests[$index].listener" "$RERUN_DIR/test-matrix.yaml")
    local transport=$(yq eval ".tests[$index].transport" "$RERUN_DIR/test-matrix.yaml")

    echo "[$((index + 1))/$test_count] $name"

    start=$(date +%s)
    if bash scripts/run-single-test.sh "$name" "$dialer" "$listener" "$transport"; then
        status="pass"
        exit_code=0
    else
        status="fail"
        exit_code=1
    fi
    end=$(date +%s)
    duration=$((end - start))

    # Append to results (with locking)
    (
        flock -x 200
        cat >> "$RERUN_DIR/results.yaml.tmp" <<RESULT
  - name: $name
    status: $status
    exitCode: $exit_code
    duration: ${duration}s
    dialer: $dialer
    listener: $listener
    transport: $transport
RESULT
    ) 200>/tmp/rerun-results.lock

    return $exit_code
}

export -f run_test
export RERUN_DIR

# Run tests in parallel using xargs
# Note: Some tests may fail, but we want to continue to collect results
# So we use || true to ensure xargs exit code doesn't stop the script
seq 0 $((test_count - 1)) | xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}' || true

# Calculate end time and duration
RERUN_END_TIME=$(date +%s)
RERUN_DURATION=$((RERUN_END_TIME - RERUN_START_TIME))

# Cleanup global services
echo ""
echo "╲ Stopping global services..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
bash scripts/stop-global-services.sh

# Collect results
echo ""
echo "╲ Collecting results..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Count pass/fail
PASSED=$(grep -c "status: pass" "$RERUN_DIR/results.yaml.tmp" || true)
FAILED=$(grep -c "status: fail" "$RERUN_DIR/results.yaml.tmp" || true)
PASSED=${PASSED:-0}
FAILED=${FAILED:-0}

# Generate final results.yaml
cat > "$RERUN_DIR/results.yaml" <<RESULTS_EOF
metadata:
  testPass: rerun-$RERUN_TIMESTAMP
  originalTestPass: $(yq eval '.metadata.testPass' results.yaml 2>/dev/null || echo "unknown")
  startedAt: $(date -d @$RERUN_START_TIME -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -r $RERUN_START_TIME -u +%Y-%m-%dT%H:%M:%SZ)
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration: ${RERUN_DURATION}s
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: $WORKER_COUNT

summary:
  total: $test_count
  passed: $PASSED
  failed: $FAILED

tests:
RESULTS_EOF

cat "$RERUN_DIR/results.yaml.tmp" >> "$RERUN_DIR/results.yaml"
rm "$RERUN_DIR/results.yaml.tmp"

# Collect failed test names
FAILED_TESTS=()
if [ "$FAILED" -gt 0 ]; then
    readarray -t FAILED_TESTS < <(yq eval '.tests[] | select(.status == "fail") | .name' "$RERUN_DIR/results.yaml")
fi

echo "→ Results:"
echo "  → Total: $test_count"
echo "  ✓ Passed: $PASSED"
echo "  ✗ Failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then
    for test_name in "${FAILED_TESTS[@]}"; do
        echo "    - $test_name"
    done
fi
echo ""

# Display execution time
HOURS=$((RERUN_DURATION / 3600))
MINUTES=$(((RERUN_DURATION % 3600) / 60))
SECONDS=$((RERUN_DURATION % 60))
printf "→ Total time: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "╲ ✓ All tests passed!"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
else
    echo "╲ ✗ $FAILED test(s) failed"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
fi

# Generate dashboard
echo ""
echo "╲ Generating results dashboard..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ bash scripts/generate-dashboard.sh"
bash scripts/generate-dashboard.sh

echo ""
echo "╲ ✓ Re-run complete"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ Results saved to: re-runs/$RERUN_TIMESTAMP/"
echo "  ✓ results.yaml"
echo "  ✓ results.md"
echo "  ✓ logs/"
EOF

chmod +x "$SNAPSHOT_DIR/re-run.sh"

# Create README
echo "→ Creating README.md..."
cat > "$SNAPSHOT_DIR/README.md" <<EOF
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
- **docker-images/** - Saved Docker images for reproducibility
- **docker-compose/** - Generated docker compose files
- **logs/** - Test execution logs
- **re-run.sh** - Script to reproduce this test run

## Re-running Tests

To reproduce this test run on any machine with bash, docker, git, yq, wget, and unzip:

\`\`\`bash
./re-run.sh [options]
\`\`\`

Options:
- \`--help, -h\`: Show help information
- \`--force-rebuild\`: Force rebuilding all Docker images before re-running tests

Examples:
\`\`\`bash
./re-run.sh                  # Use cached Docker images from snapshot
./re-run.sh --force-rebuild  # Rebuild images from source before running
./re-run.sh --help           # Show help information
\`\`\`

This will:
1. Validate all required snapshots are present
2. Load Docker images from snapshot (or rebuild if needed/requested)
3. Build only the implementations required for tests (based on impls.yaml and test-matrix.yaml)
4. Start global services (Redis, Relay)
5. Re-run all tests with the same configuration in parallel
6. Generate new results in re-runs/ subdirectory

## Test Summary

$(grep -A 10 "^summary:" "$SNAPSHOT_DIR/results.yaml" || echo "See results.yaml for details")

## Original Results

See \`results.md\` for the full test dashboard from the original run.

---

*Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)*
EOF

# Create archive
echo "→ Creating archive..."
cd "$CACHE_DIR/test-runs"
tar -czf "${test_pass}.tar.gz" "$test_pass"

snapshot_size=$(du -h "${test_pass}.tar.gz" | cut -f1)

echo ""
echo "╲ ✓ Snapshot created successfully"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "→ Snapshot: $test_pass"
echo "→ Location: $SNAPSHOT_DIR"
echo "→ Archive: $CACHE_DIR/test-runs/${test_pass}.tar.gz ($snapshot_size)"
echo ""
echo "→ To extract and re-run:"
echo "    tar -xzf $CACHE_DIR/test-runs/${test_pass}.tar.gz"
echo "    cd $test_pass"
echo "    ./re-run.sh"

