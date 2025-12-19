#!/bin/bash
# Generate test matrix from images.yaml with dialer × listener combinations
# Pattern: <dialer> x <listener> (<transport>, <secureChannel>, <muxer>)
# Similar to transport/lib/generate-tests.sh

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
source "../lib/lib-test-filtering.sh"
source "../lib/lib-test-aliases.sh"
source "../lib/lib-test-caching.sh"
source "../lib/lib-filter-engine.sh"
source "lib/lib-perf.sh"

# Load test aliases
load_aliases

# Get all entity IDs for negation expansion and ignored test generation
all_image_ids=($(yq eval '.implementations[].id' images.yaml))
all_baseline_ids=($(yq eval '.baselines[].id' images.yaml))

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

# Save original filters for display
ORIGINAL_SELECT="$TEST_SELECT"
ORIGINAL_IGNORE="$TEST_IGNORE"
ORIGINAL_BASELINE_SELECT="$BASELINE_SELECT"
ORIGINAL_BASELINE_IGNORE="$BASELINE_IGNORE"

# Display filters
if [ -n "$ORIGINAL_SELECT" ]; then
    echo "  → Test select: $ORIGINAL_SELECT"
else
    echo "  → No test-select specified (will include all implementations)"
fi

if [ -n "$ORIGINAL_IGNORE" ]; then
    echo "  → Test ignore: $ORIGINAL_IGNORE"
else
    echo "  → No test-ignore specified"
fi

if [ -n "$ORIGINAL_BASELINE_SELECT" ]; then
    echo "  → Baseline select: $ORIGINAL_BASELINE_SELECT"
else
    echo "  → No baseline-select specified (will include all baselines)"
fi

if [ -n "$ORIGINAL_BASELINE_IGNORE" ]; then
    echo "  → Baseline ignore: $ORIGINAL_BASELINE_IGNORE"
else
    echo "  → No baseline-ignore specified"
fi
echo ""

# Use TEST_RUN_KEY from parent (run.sh) if available
# Otherwise compute cache key from images.yaml + all filters + debug
if [ -n "${TEST_RUN_KEY:-}" ]; then
    cache_key="$TEST_RUN_KEY"
    echo "  → Using test run key: $cache_key"
else
    # Fallback for standalone execution
    cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "$BASELINE_SELECT" "$BASELINE_IGNORE" "" "" "$DEBUG")
    echo "  → Computed cache key: ${cache_key:0:8}"
fi

# Check cache (with optional force rebuild)
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$TEST_PASS_DIR" "$FORCE_MATRIX_REBUILD"; then
    exit 0
fi

echo ""

# Filter implementations and baselines upfront using global filter_entity_list function
echo "  → Filtering implementations..."
mapfile -t filtered_image_ids < <(filter_entity_list "implementations" "$TEST_SELECT" "$TEST_IGNORE")
echo "    ✓ Filtered to ${#filtered_image_ids[@]} implementations (${#all_image_ids[@]} total)"

echo "  → Filtering baselines..."
mapfile -t filtered_baseline_ids < <(filter_entity_list "baselines" "$BASELINE_SELECT" "$BASELINE_IGNORE")
echo "    ✓ Filtered to ${#filtered_baseline_ids[@]} baselines (${#all_baseline_ids[@]} total)"

echo ""

# Load baseline data for ALL baselines (needed for ignored test generation)
echo "  → Loading baseline data into memory..."

declare -A baseline_transports
declare -A baseline_secure
declare -A baseline_muxers
declare -A baseline_server

for baseline_id in "${all_baseline_ids[@]}"; do
    transports=$(yq eval ".baselines[] | select(.id == \"$baseline_id\") | .transports | join(\" \")" images.yaml)
    secure=$(yq eval ".baselines[] | select(.id == \"$baseline_id\") | .secureChannels | join(\" \")" images.yaml)
    muxers=$(yq eval ".baselines[] | select(.id == \"$baseline_id\") | .muxers | join(\" \")" images.yaml)
    server=$(yq eval ".baselines[] | select(.id == \"$baseline_id\") | .server" images.yaml)

    baseline_transports["$baseline_id"]="$transports"
    baseline_secure["$baseline_id"]="$secure"
    baseline_muxers["$baseline_id"]="$muxers"
    baseline_server["$baseline_id"]="$server"
done

echo "    ✓ Loaded data for ${#all_baseline_ids[@]} baselines"

# Load main implementation data for ALL implementations (needed for ignored test generation)
echo "  → Loading implementation data into memory..."

declare -A image_transports
declare -A image_secure
declare -A image_muxers
declare -A image_server

for image_id in "${all_image_ids[@]}"; do
    transports=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .transports | join(\" \")" images.yaml)
    secure=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .secureChannels | join(\" \")" images.yaml)
    muxers=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .muxers | join(\" \")" images.yaml)
    server=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .server" images.yaml)

    image_transports["$image_id"]="$transports"
    image_secure["$image_id"]="$secure"
    image_muxers["$image_id"]="$muxers"
    image_server["$image_id"]="$server"
done

echo "    ✓ Loaded data for ${#all_image_ids[@]} implementations"
echo ""

# Note: Baseline filtering now uses generic filter_matches() from lib-filter-engine.sh
# The duplicate baseline_matches_select() and baseline_should_ignore() functions
# have been removed.

# Initialize counters and arrays for ignored tests
baseline_num=0
ignored_baseline_num=0
test_num=0
ignored_test_num=0
ignored_baseline_tests=()
ignored_main_tests=()

echo "╲ Generating baseline test combinations..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Create test matrix header
cat > "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
metadata:
  testPass: ${TEST_PASS_NAME:-perf-$(date +%H%M%S-%d-%m-%Y)}
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
# Loop through ALL baselines and track selected vs ignored
for dialer_id in "${all_baseline_ids[@]}"; do
    dialer_transports="${baseline_transports[$dialer_id]}"
    dialer_secure="${baseline_secure[$dialer_id]}"
    dialer_muxers="${baseline_muxers[$dialer_id]}"
    dialer_server="${baseline_server[$dialer_id]}"

    for listener_id in "${all_baseline_ids[@]}"; do
        # Check if BOTH dialer AND listener are in filtered baseline list
        test_is_selected=false
        if [[ " ${filtered_baseline_ids[*]} " =~ " ${dialer_id} " ]] && [[ " ${filtered_baseline_ids[*]} " =~ " ${listener_id} " ]]; then
            test_is_selected=true
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

                # Add to selected or ignored list based on entity membership
                if [ "$test_is_selected" = true ]; then
                    # Selected baseline test
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
                    # Ignored baseline test
                    ignored_baseline_tests+=("$test_name|$dialer_id|$listener_id|$dialer_server|$listener_server|$transport|null|null")
                    ((ignored_baseline_num++))
                fi
            else
                # Regular transport - needs secureChannel × muxer
                common_secure=$(get_common "$dialer_secure" "$listener_secure")
                common_muxers=$(get_common "$dialer_muxers" "$listener_muxers")

                # Allow raw transport if both have empty security/muxing (baseline case)
                # Debug logging
                if [ "${DEBUG:-false}" = "true" ]; then
                    if [ "$dialer_id" = "iperf-v3.0" ] || [ "$listener_id" = "iperf-v3.0" ]; then
                        echo "DEBUG: Processing iperf baseline" >&2
                        echo "  dialer=$dialer_id, listener=$listener_id, transport=$transport" >&2
                        echo "  common_secure='$common_secure', common_muxers='$common_muxers'" >&2
                        echo "  dialer_secure='$dialer_secure', dialer_muxers='$dialer_muxers'" >&2
                        echo "  listener_secure='$listener_secure', listener_muxers='$listener_muxers'" >&2
                    fi
                fi

                if [ -z "$common_secure" ] && [ -z "$common_muxers" ] && \
                   [ -z "$dialer_secure" ] && [ -z "$dialer_muxers" ] && \
                   [ -z "$listener_secure" ] && [ -z "$listener_muxers" ]; then
                    # Raw transport baseline (no security or muxing)
                    test_name="$dialer_id x $listener_id ($transport)"

                    if [ "${DEBUG:-false}" = "true" ]; then
                        echo "DEBUG: Creating raw transport baseline: $test_name" >&2
                    fi

                    # Add to selected or ignored list
                    if [ "$test_is_selected" = true ]; then
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
                        # Ignored baseline test
                        ignored_baseline_tests+=("$test_name|$dialer_id|$listener_id|$dialer_server|$listener_server|$transport|null|null")
                        ((ignored_baseline_num++))
                    fi
                else
                    # Regular transport with security and muxing
                    [ -z "$common_secure" ] && continue
                    [ -z "$common_muxers" ] && continue

                    for secure in $common_secure; do
                        for muxer in $common_muxers; do
                            test_name="$dialer_id x $listener_id ($transport, $secure, $muxer)"

                            # Add to selected or ignored list
                            if [ "$test_is_selected" = true ]; then
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
                            else
                                # Ignored baseline test
                                ignored_baseline_tests+=("$test_name|$dialer_id|$listener_id|$dialer_server|$listener_server|$transport|$secure|$muxer")
                                ((ignored_baseline_num++))
                            fi
                        done
                    done
                fi
            fi
        done
    done
done

echo "  ✓ Generated $baseline_num baseline tests"
echo ""

# Start main tests section
cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF

tests:
EOF

echo "╲ Generating main test combinations..."
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Iterate through ALL implementations and track selected vs ignored
for dialer_id in "${all_image_ids[@]}"; do
    dialer_transports="${image_transports[$dialer_id]}"
    dialer_secure="${image_secure[$dialer_id]}"
    dialer_muxers="${image_muxers[$dialer_id]}"
    dialer_server="${image_server[$dialer_id]}"

    for listener_id in "${all_image_ids[@]}"; do
        # Check if BOTH dialer AND listener are in filtered implementation list
        test_is_selected=false
        if [[ " ${filtered_image_ids[*]} " =~ " ${dialer_id} " ]] && [[ " ${filtered_image_ids[*]} " =~ " ${listener_id} " ]]; then
            test_is_selected=true
        fi

        listener_transports="${image_transports[$listener_id]}"
        listener_secure="${image_secure[$listener_id]}"
        listener_muxers="${image_muxers[$listener_id]}"
        listener_server="${image_server[$listener_id]}"

        # Find common transports
        common_transports=$(get_common "$dialer_transports" "$listener_transports")

        # Skip if no common transports
        [ -z "$common_transports" ] && continue

        # Process each common transport
        for transport in $common_transports; do
            if is_standalone_transport "$transport"; then
                # Standalone transport - no secureChannel/muxer needed
                test_name="$dialer_id x $listener_id ($transport)"

                # Add to selected or ignored list
                if [ "$test_is_selected" = true ]; then
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
                    # Ignored main test
                    ignored_main_tests+=("$test_name|$dialer_id|$listener_id|$dialer_server|$listener_server|$transport|null|null")
                    ((ignored_test_num++))
                fi

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

                        # Add to selected or ignored list
                        if [ "$test_is_selected" = true ]; then
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
                        else
                            # Ignored main test
                            ignored_main_tests+=("$test_name|$dialer_id|$listener_id|$dialer_server|$listener_server|$transport|$secure|$muxer")
                            ((ignored_test_num++))
                        fi
                    done
                done
            fi
        done
    done
done

# Output ignored baselines section
if [ ${#ignored_baseline_tests[@]} -eq 0 ]; then
    cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF

ignoredBaselines: []
EOF
else
    cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF

ignoredBaselines:
EOF
    for test_data in "${ignored_baseline_tests[@]}"; do
        IFS='|' read -r name dialer listener dialer_server listener_server transport secure muxer <<< "$test_data"
        cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
  - name: "$name"
    dialer: $dialer
    listener: $listener
    dialerServer: $dialer_server
    listenerServer: $listener_server
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
EOF
    done
fi

# Output ignored main tests section
if [ ${#ignored_main_tests[@]} -eq 0 ]; then
    cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF

ignoredTests: []
EOF
else
    cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF

ignoredTests:
EOF
    for test_data in "${ignored_main_tests[@]}"; do
        IFS='|' read -r name dialer listener dialer_server listener_server transport secure muxer <<< "$test_data"
        cat >> "$TEST_PASS_DIR/test-matrix.yaml" <<EOF
  - name: "$name"
    dialer: $dialer
    listener: $listener
    dialerServer: $dialer_server
    listenerServer: $listener_server
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
EOF
    done
fi

# Update metadata with final counts
# Use yq to update the metadata section
yq eval -i ".metadata.totalBaselines = $baseline_num" "$TEST_PASS_DIR/test-matrix.yaml"
yq eval -i ".metadata.ignoredBaselines = $ignored_baseline_num" "$TEST_PASS_DIR/test-matrix.yaml"
yq eval -i ".metadata.totalTests = $test_num" "$TEST_PASS_DIR/test-matrix.yaml"
yq eval -i ".metadata.ignoredTests = $ignored_test_num" "$TEST_PASS_DIR/test-matrix.yaml"

# Copy images.yaml for reference
cp images.yaml "$TEST_PASS_DIR/"

echo "  ✓ Generated $baseline_num baseline tests ($ignored_baseline_num ignored)"
echo "  ✓ Generated $test_num main tests ($ignored_test_num ignored)"

# Cache the generated matrix
save_to_cache "$TEST_PASS_DIR" "$cache_key" "$CACHE_DIR" "perf"

exit 0
