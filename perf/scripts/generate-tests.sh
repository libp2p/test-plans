#!/bin/bash
# Generate test matrix from impls.yaml with dialer × listener combinations
# Pattern: <dialer> x <listener> (<transport>, <secureChannel>, <muxer>)
# Similar to transport/scripts/generate-tests.sh

set -uo pipefail  # Removed -e to allow continuation on errors

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Standalone transports (don't require secureChannel/muxer)
STANDALONE_TRANSPORTS="quic quic-v1 webtransport webrtc webrtc-direct https"

# Check if transport is standalone
is_standalone_transport() {
    local transport="$1"
    echo "$STANDALONE_TRANSPORTS" | grep -qw "$transport"
}

# Source common libraries
source "../scripts/lib-test-filtering.sh"
source "../scripts/lib-test-aliases.sh"
source "../scripts/lib-test-caching.sh"
source "scripts/lib-perf.sh"

# Load test aliases
load_aliases

# Get parameters from environment
TEST_SELECT="${TEST_SELECT:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
BASELINE_SELECT="${BASELINE_SELECT:-}"
BASELINE_IGNORE="${BASELINE_IGNORE:-}"
UPLOAD_BYTES="${UPLOAD_BYTES:-1073741824}"
DOWNLOAD_BYTES="${DOWNLOAD_BYTES:-1073741824}"
ITERATIONS="${ITERATIONS:-10}"
DURATION_PER_ITERATION="${DURATION_PER_ITERATION:-20}"
LATENCY_ITERATIONS="${LATENCY_ITERATIONS:-100}"

# Expand aliases and negations (but don't display yet)
ORIGINAL_SELECT="$TEST_SELECT"
ORIGINAL_IGNORE="$TEST_IGNORE"
ORIGINAL_BASELINE_SELECT="$BASELINE_SELECT"
ORIGINAL_BASELINE_IGNORE="$BASELINE_IGNORE"

if [ -n "$TEST_SELECT" ]; then
    TEST_SELECT=$(expand_all_patterns "$TEST_SELECT" "impls.yaml")
fi

if [ -n "$TEST_IGNORE" ]; then
    TEST_IGNORE=$(expand_all_patterns "$TEST_IGNORE" "impls.yaml")
fi

if [ -n "$BASELINE_SELECT" ]; then
    BASELINE_SELECT=$(expand_all_patterns "$BASELINE_SELECT" "impls.yaml")
fi

if [ -n "$BASELINE_IGNORE" ]; then
    BASELINE_IGNORE=$(expand_all_patterns "$BASELINE_IGNORE" "impls.yaml")
fi

# Pre-parse select and ignore patterns
declare -a SELECT_PATTERNS=()
declare -a IGNORE_PATTERNS=()
declare -a BASELINE_SELECT_PATTERNS=()
declare -a BASELINE_IGNORE_PATTERNS=()

if [ -n "$TEST_SELECT" ]; then
    IFS='|' read -ra SELECT_PATTERNS <<< "$TEST_SELECT"
fi

if [ -n "$TEST_IGNORE" ]; then
    IFS='|' read -ra IGNORE_PATTERNS <<< "$TEST_IGNORE"
fi

if [ -n "$BASELINE_SELECT" ]; then
    IFS='|' read -ra BASELINE_SELECT_PATTERNS <<< "$BASELINE_SELECT"
fi

if [ -n "$BASELINE_IGNORE" ]; then
    IFS='|' read -ra BASELINE_IGNORE_PATTERNS <<< "$BASELINE_IGNORE"
fi

# Output section header
echo ""
echo "╲ Test Matrix Generation"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Display expanded filters (AFTER header, like transport)
if [ -n "$ORIGINAL_SELECT" ]; then
    echo "→ Test select: $ORIGINAL_SELECT"
    echo "  → Expanded to: $TEST_SELECT"
else
    echo "→ No test-select specified (will include all tests)"
fi

if [ -n "$ORIGINAL_IGNORE" ]; then
    echo "→ Test ignore: $ORIGINAL_IGNORE"
    echo "  → Expanded to: $TEST_IGNORE"
else
    echo "→ No test-ignore specified"
fi

if [ -n "$ORIGINAL_BASELINE_SELECT" ]; then
    echo "→ Baseline select: $ORIGINAL_BASELINE_SELECT"
    echo "  → Expanded to: $BASELINE_SELECT"
else
    echo "→ No baseline-select specified (will include all baselines)"
fi

if [ -n "$ORIGINAL_BASELINE_IGNORE" ]; then
    echo "→ Baseline ignore: $ORIGINAL_BASELINE_IGNORE"
    echo "  → Expanded to: $BASELINE_IGNORE"
else
    echo "→ No baseline-ignore specified"
fi

# Compute cache key from impls.yaml + all filters + debug
cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "$BASELINE_SELECT" "$BASELINE_IGNORE" "" "" "$DEBUG")
echo "→ Computed cache key: ${cache_key:0:8}"

# Check cache (with optional force rebuild)
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$TEST_PASS_DIR" "$FORCE_MATRIX_REBUILD"; then
    exit 0
fi

echo ""

# Load baseline data
baseline_count=$(yq eval '.baselines | length' impls.yaml)
echo "→ Found $baseline_count baselines in impls.yaml"
echo "→ Loading baseline data into memory..."

declare -A baseline_transports
declare -A baseline_secure
declare -A baseline_muxers
declare -A baseline_server
declare -a baseline_ids

for ((i=0; i<baseline_count; i++)); do
    id=$(yq eval ".baselines[$i].id" impls.yaml)
    transports=$(yq eval ".baselines[$i].transports | join(\" \")" impls.yaml)
    secure=$(yq eval ".baselines[$i].secureChannels | join(\" \")" impls.yaml)
    muxers=$(yq eval ".baselines[$i].muxers | join(\" \")" impls.yaml)
    server=$(yq eval ".baselines[$i].server" impls.yaml)

    baseline_ids+=("$id")
    baseline_transports["$id"]="$transports"
    baseline_secure["$id"]="$secure"
    baseline_muxers["$id"]="$muxers"
    baseline_server["$id"]="$server"
done

echo "  ✓ Loaded ${#baseline_ids[@]} baselines into memory"
if [ ${#BASELINE_SELECT_PATTERNS[@]} -gt 0 ]; then
    echo "  ✓ Loaded ${#BASELINE_SELECT_PATTERNS[@]} baseline select patterns"
fi
if [ ${#BASELINE_IGNORE_PATTERNS[@]} -gt 0 ]; then
    echo "  ✓ Loaded ${#BASELINE_IGNORE_PATTERNS[@]} baseline ignore patterns"
fi

# Load main implementation data
impl_count=$(yq eval '.implementations | length' impls.yaml)
echo "→ Found $impl_count implementations in impls.yaml"
echo "→ Loading implementation data into memory..."

declare -A impl_transports
declare -A impl_secure
declare -A impl_muxers
declare -A impl_server
declare -a impl_ids

for ((i=0; i<impl_count; i++)); do
    id=$(yq eval ".implementations[$i].id" impls.yaml)
    transports=$(yq eval ".implementations[$i].transports | join(\" \")" impls.yaml)
    secure=$(yq eval ".implementations[$i].secureChannels | join(\" \")" impls.yaml)
    muxers=$(yq eval ".implementations[$i].muxers | join(\" \")" impls.yaml)
    server=$(yq eval ".implementations[$i].server" impls.yaml)

    impl_ids+=("$id")
    impl_transports["$id"]="$transports"
    impl_secure["$id"]="$secure"
    impl_muxers["$id"]="$muxers"
    impl_server["$id"]="$server"
done

echo "  ✓ Loaded ${#impl_ids[@]} implementations into memory"
if [ ${#SELECT_PATTERNS[@]} -gt 0 ]; then
    echo "  ✓ Loaded ${#SELECT_PATTERNS[@]} select patterns"
fi
if [ ${#IGNORE_PATTERNS[@]} -gt 0 ]; then
    echo "  ✓ Loaded ${#IGNORE_PATTERNS[@]} ignore patterns"
fi
echo ""

# Helper functions for baseline filtering
baseline_matches_select() {
    local baseline_id="$1"
    [ ${#BASELINE_SELECT_PATTERNS[@]} -eq 0 ] && return 0
    for select in "${BASELINE_SELECT_PATTERNS[@]}"; do
        [[ "$baseline_id" == *"$select"* ]] && return 0
    done
    return 1
}

baseline_should_ignore() {
    local test_name="$1"
    [ ${#BASELINE_IGNORE_PATTERNS[@]} -eq 0 ] && return 1

    for ignore in "${BASELINE_IGNORE_PATTERNS[@]}"; do
        if [[ "$ignore" == !* ]] || [[ "$ignore" == \\!* ]]; then
            local pattern="${ignore#!}"
            pattern="${pattern#\\!}"
            local dialer=$(echo "$test_name" | sed 's/ x .*//')
            local listener=$(echo "$test_name" | sed 's/.* x //' | sed 's/ (.*//')
            if [[ "$dialer" != *"$pattern"* ]] || [[ "$listener" != *"$pattern"* ]]; then
                return 0
            fi
        else
            if [[ "$test_name" == *"$ignore"* ]]; then
                return 0
            fi
        fi
    done
    return 1
}

# Initialize counters
test_num=0
baseline_num=0

echo "╲ Generating baseline test combinations..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Create test matrix header
cat > "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
metadata:
  testPass: $TEST_PASS_NAME
  startedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  select: |-
    $TEST_SELECT
  ignore: |-
    $TEST_IGNORE
  baselineSelect: |-
    $BASELINE_SELECT
  baselineIgnore: |-
    $BASELINE_IGNORE
  uploadBytes: $UPLOAD_BYTES
  downloadBytes: $DOWNLOAD_BYTES
  iterations: $ITERATIONS
  durationPerIteration: $DURATION_PER_ITERATION
  latencyIterations: $LATENCY_ITERATIONS

baselines:
EOF

# Generate baseline tests (baseline x baseline combinations)
for dialer_id in "${baseline_ids[@]}"; do
    # Apply baseline select filter
    if [ ${#BASELINE_SELECT_PATTERNS[@]} -gt 0 ]; then
        baseline_matches_select "$dialer_id" || baseline_matches_select "$dialer_id" || continue
    fi

    dialer_transports="${baseline_transports[$dialer_id]}"
    dialer_secure="${baseline_secure[$dialer_id]}"
    dialer_muxers="${baseline_muxers[$dialer_id]}"
    dialer_server="${baseline_server[$dialer_id]}"

    for listener_id in "${baseline_ids[@]}"; do
        # Apply baseline select filter
        if [ ${#BASELINE_SELECT_PATTERNS[@]} -gt 0 ]; then
            baseline_matches_select "$dialer_id" || baseline_matches_select "$listener_id" || continue
        fi

        listener_transports="${baseline_transports[$listener_id]}"
        listener_secure="${baseline_secure[$listener_id]}"
        listener_muxers="${baseline_muxers[$listener_id]}"
        listener_server="${baseline_server[$listener_id]}"

        # Find common transports
        common_transports=$(get_common "$dialer_transports" "$listener_transports")
        [ -z "$common_transports" ] && continue

        # Process each common transport
        for transport in $common_transports; do
            if is_standalone_transport "$transport"; then
                # Standalone transport
                test_name="$dialer_id x $listener_id ($transport)"

                # Check ignore
                baseline_should_ignore "$test_name" && continue

                # Add baseline test
                cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
  - id: baseline-$baseline_num
    name: "$test_name"
    dialer: $dialer_id
    listener: $listener_id
    dialerServer: $dialer_server
    listenerServer: $listener_server
    transport: $transport
    secureChannel: null
    muxer: null
    uploadBytes: $UPLOAD_BYTES
    downloadBytes: $DOWNLOAD_BYTES
    uploadIterations: $ITERATIONS
    downloadIterations: $ITERATIONS
    latencyIterations: $LATENCY_ITERATIONS
    durationPerIteration: $DURATION_PER_ITERATION
EOF
                ((baseline_num++))
            else
                # Regular transport - needs secureChannel × muxer
                common_secure=$(get_common "$dialer_secure" "$listener_secure")
                common_muxers=$(get_common "$dialer_muxers" "$listener_muxers")
                [ -z "$common_secure" ] && continue
                [ -z "$common_muxers" ] && continue

                for secure in $common_secure; do
                    for muxer in $common_muxers; do
                        test_name="$dialer_id x $listener_id ($transport, $secure, $muxer)"
                        baseline_should_ignore "$test_name" && continue

                        cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
  - id: baseline-$baseline_num
    name: "$test_name"
    dialer: $dialer_id
    listener: $listener_id
    dialerServer: $dialer_server
    listenerServer: $listener_server
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    uploadBytes: $UPLOAD_BYTES
    downloadBytes: $DOWNLOAD_BYTES
    uploadIterations: $ITERATIONS
    downloadIterations: $ITERATIONS
    latencyIterations: $LATENCY_ITERATIONS
    durationPerIteration: $DURATION_PER_ITERATION
EOF
                        ((baseline_num++))
                    done
                done
            fi
        done
    done
done

echo "✓ Generated $baseline_num baseline tests"
echo ""

# Start main tests section
cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF

tests:
EOF

echo "╲ Generating main test combinations..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Iterate through all dialer/listener pairs
for dialer_id in "${impl_ids[@]}"; do
    dialer_transports="${impl_transports[$dialer_id]}"
    dialer_secure="${impl_secure[$dialer_id]}"
    dialer_muxers="${impl_muxers[$dialer_id]}"
    dialer_server="${impl_server[$dialer_id]}"

    for listener_id in "${impl_ids[@]}"; do
        # When TEST_SELECT is specified, include test if EITHER dialer OR listener matches
        if [ ${#SELECT_PATTERNS[@]} -gt 0 ]; then
            impl_matches_select "$dialer_id" || impl_matches_select "$listener_id" || continue
        fi

        listener_transports="${impl_transports[$listener_id]}"
        listener_secure="${impl_secure[$listener_id]}"
        listener_muxers="${impl_muxers[$listener_id]}"
        listener_server="${impl_server[$listener_id]}"

        # Find common transports
        common_transports=$(get_common "$dialer_transports" "$listener_transports")

        # Skip if no common transports
        [ -z "$common_transports" ] && continue

        # Process each common transport
        for transport in $common_transports; do
            if is_standalone_transport "$transport"; then
                # Standalone transport - no secureChannel/muxer needed
                test_name="$dialer_id x $listener_id ($transport)"

                # Check select/ignore
                if ! matches_select "$test_name"; then
                    continue
                fi

                if should_ignore "$test_name"; then
                    continue
                fi

                # Single test with all 3 measurements (upload, download, latency)
                cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
  - id: test-$test_num
    name: "$test_name"
    dialer: $dialer_id
    listener: $listener_id
    dialerServer: $dialer_server
    listenerServer: $listener_server
    transport: $transport
    secureChannel: null
    muxer: null
    uploadBytes: $UPLOAD_BYTES
    downloadBytes: $DOWNLOAD_BYTES
    uploadIterations: $ITERATIONS
    downloadIterations: $ITERATIONS
    latencyIterations: $LATENCY_ITERATIONS
    durationPerIteration: $DURATION_PER_ITERATION
EOF
                ((test_num++))

            else
                # Regular transport - needs secureChannel × muxer combinations
                common_secure=$(get_common "$dialer_secure" "$listener_secure")
                common_muxers=$(get_common "$dialer_muxers" "$listener_muxers")

                # Skip if no common secureChannel or muxer
                [ -z "$common_secure" ] && continue
                [ -z "$common_muxers" ] && continue

                # Generate all combinations
                for secure in $common_secure; do
                    for muxer in $common_muxers; do
                        test_name="$dialer_id x $listener_id ($transport, $secure, $muxer)"

                        # Check select/ignore
                        if ! matches_select "$test_name"; then
                            continue
                        fi

                        if should_ignore "$test_name"; then
                            continue
                        fi

                        # Single test with all 3 measurements
                        cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
  - id: test-$test_num
    name: "$test_name"
    dialer: $dialer_id
    listener: $listener_id
    dialerServer: $dialer_server
    listenerServer: $listener_server
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    uploadBytes: $UPLOAD_BYTES
    downloadBytes: $DOWNLOAD_BYTES
    uploadIterations: $ITERATIONS
    downloadIterations: $ITERATIONS
    latencyIterations: $LATENCY_ITERATIONS
    durationPerIteration: $DURATION_PER_ITERATION
EOF
                        ((test_num++))
                    done
                done
            fi
        done
    done
done

# Update metadata with final counts
# Use yq to update the metadata section
yq eval -i ".metadata.totalBaselines = $baseline_num" "$TEST_PASS_DIR/test-matrix.yaml"
yq eval -i ".metadata.totalTests = $test_num" "$TEST_PASS_DIR/test-matrix.yaml"

# Copy impls.yaml for reference
cp impls.yaml "$TEST_PASS_DIR/"

echo "✓ Generated $test_num main tests"

# Cache the generated matrix
save_to_cache "$TEST_PASS_DIR" "$cache_key" "$CACHE_DIR"

echo ""

exit 0
