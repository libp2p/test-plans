#!/bin/bash
# Source formatting library
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib}"
source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"
# Generate test matrix from images.yaml with 3D combinations (transport × secureChannel × muxer)
# Outputs test-matrix.yaml with content-addressed caching

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
CLI_TEST_SELECT="${1:-}"
CLI_TEST_IGNORE="${2:-}"
DEBUG="${3:-false}"  # Optional: debug mode flag
FORCE_MATRIX_REBUILD="${4:-false}"  # Optional: force matrix rebuild
OUTPUT_DIR="${TEST_PASS_DIR:-.}"  # Use TEST_PASS_DIR if set, otherwise current directory

# Standalone transports (don't require muxer/secureChannel)
STANDALONE_TRANSPORTS="quic quic-v1 webtransport webrtc webrtc-direct"

# Check if transport is standalone (doesn't need muxer/secureChannel)
is_standalone_transport() {
    local transport="$1"
    echo "$STANDALONE_TRANSPORTS" | grep -qw "$transport"
}

# Source common libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$SCRIPT_DIR/../../lib}"
source "$SCRIPT_LIB_DIR/lib-test-aliases.sh"
source "$SCRIPT_LIB_DIR/lib-test-filtering.sh"
source "$SCRIPT_LIB_DIR/lib-test-caching.sh"
source "$SCRIPT_LIB_DIR/lib-filter-engine.sh"

# Load test aliases from images.yaml
load_aliases

# Get all implementation IDs for negation expansion
all_image_ids=($(yq eval '.implementations[].id' images.yaml))

# Use test select and ignore values from CLI arguments
TEST_SELECT="$CLI_TEST_SELECT"
TEST_IGNORE="$CLI_TEST_IGNORE"

echo ""
print_header "Test Matrix Generation"

# Display filters (will expand during filtering)
if [ -n "$TEST_SELECT" ]; then
    echo "→ Test select: $TEST_SELECT"
else
    echo "→ No test-select specified (will include all implementations)"
fi

if [ -n "$TEST_IGNORE" ]; then
    echo "→ Test ignore: $TEST_IGNORE"
else
    echo "→ No test-ignore specified"
fi

# Use TEST_RUN_KEY from parent (run.sh) if available
# Otherwise compute cache key from images.yaml + select + ignore + debug
if [ -n "${TEST_RUN_KEY:-}" ]; then
    cache_key="$TEST_RUN_KEY"
    echo "→ Using test run key: $cache_key"
else
    # Fallback for standalone execution
    cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "" "" "" "" "$DEBUG")
    echo "→ Computed cache key: ${cache_key:0:8}"
fi

# Check cache (with optional force rebuild)
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$OUTPUT_DIR" "$FORCE_MATRIX_REBUILD" "transport"; then
    exit 0
fi

echo ""

# Filter implementations upfront using global filter_names function
echo ""
echo "→ Filtering implementations..."
mapfile -t filtered_image_ids < <(filter_entity_list "implementations" "$TEST_SELECT" "$TEST_IGNORE")
echo "  ✓ Filtered to ${#filtered_image_ids[@]} implementations"

# Display filtered implementations if small list
if [ ${#filtered_image_ids[@]} -le 10 ]; then
    for image_id in "${filtered_image_ids[@]}"; do
        echo "    - $image_id"
    done
fi

# Load implementation data only for filtered implementations
echo "→ Loading implementation data into memory..."
declare -A image_transports    # image_transports[rust-v0.56]="tcp ws quic-v1"
declare -A image_secure        # image_secure[rust-v0.56]="tls noise"
declare -A image_muxers        # image_muxers[rust-v0.56]="yamux mplex"
declare -A image_dial_only     # image_dial_only[chromium-rust-v0.54]="webtransport webrtc-direct ws"

# Load data for each filtered implementation
for image_id in "${filtered_image_ids[@]}"; do
    transports=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .transports | join(\" \")" images.yaml)
    secure=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .secureChannels | join(\" \")" images.yaml)
    muxers=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .muxers | join(\" \")" images.yaml)
    dial_only=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .dialOnly | join(\" \")" images.yaml 2>/dev/null || echo "")

    image_transports["$image_id"]="$transports"
    image_secure["$image_id"]="$secure"
    image_muxers["$image_id"]="$muxers"
    image_dial_only["$image_id"]="$dial_only"
done

echo "  ✓ Loaded data for ${#filtered_image_ids[@]} filtered implementations"

# Check if a transport can be used with an implementation as listener
# Returns 0 (true) if transport can be used as listener, 1 (false) if dialOnly
can_be_listener_for_transport() {
    local image_id="$1"
    local transport="$2"
    local dial_only_transports="${image_dial_only[$image_id]:-}"

    # If no dialOnly restrictions, can always be listener
    [ -z "$dial_only_transports" ] && return 0

    # Check if transport is in dialOnly list
    if [[ " $dial_only_transports " == *" $transport "* ]]; then
        return 1  # Cannot be listener for this transport
    fi

    return 0  # Can be listener
}

echo ""
echo "╲ Generating test combinations..."

# Initialize test lists
tests=()
test_num=0

# Iterate through FILTERED implementations only (no inline filtering needed!)
for dialer_id in "${filtered_image_ids[@]}"; do
    dialer_transports="${image_transports[$dialer_id]}"
    dialer_secure="${image_secure[$dialer_id]}"
    dialer_muxers="${image_muxers[$dialer_id]}"

    for listener_id in "${filtered_image_ids[@]}"; do
        # No filtering needed - already filtered upfront!

        listener_transports="${image_transports[$listener_id]}"
        listener_secure="${image_secure[$listener_id]}"
        listener_muxers="${image_muxers[$listener_id]}"

        # Find common transports (much faster than grep)
        common_transports=$(get_common "$dialer_transports" "$listener_transports")

        # Skip if no common transports
        [ -z "$common_transports" ] && continue

        # Process each common transport
        for transport in $common_transports; do
            # Check if listener can handle this transport (not in dialOnly list)
            if ! can_be_listener_for_transport "$listener_id" "$transport"; then
                continue  # Skip: listener has this transport in dialOnly
            fi

            if is_standalone_transport "$transport"; then
                # Standalone transport
                test_name="$dialer_id x $listener_id ($transport)"

                # No filtering needed - implementations already filtered upfront
                test_num=$((test_num + 1))
                tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null")

            else
                # Non-standalone: need secure + muxer combinations
                common_secure=$(get_common "$dialer_secure" "$listener_secure")
                common_muxers=$(get_common "$dialer_muxers" "$listener_muxers")

                # Skip if no common secure channels or muxers
                [ -z "$common_secure" ] && continue
                [ -z "$common_muxers" ] && continue

                # Generate all valid combinations
                for secure in $common_secure; do
                    for muxer in $common_muxers; do
                        test_name="$dialer_id x $listener_id ($transport, $secure, $muxer)"

                        # No filtering needed - implementations already filtered upfront
                        test_num=$((test_num + 1))
                        tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer")
                    done
                done
            fi
        done
    done
done

echo "✓ Generated ${#tests[@]} tests"

echo ""

# Generate test-matrix.yaml
cat > "$OUTPUT_DIR/test-matrix.yaml" <<EOF
metadata:
  generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  select: $TEST_SELECT
  ignore: $TEST_IGNORE
  totalTests: ${#tests[@]}
  ignoredTests: 0
  debug: $DEBUG

tests:
EOF

for test in "${tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer <<< "$test"

    # Get source types and commits (only for github-type implementations)
    dialer_source_type=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.type" images.yaml)
    listener_source_type=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.type" images.yaml)

    # Only get commits for github-type sources
    if [ "$dialer_source_type" = "github" ]; then
        dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" images.yaml)
        dialer_snapshot="snapshots/$dialer_commit.zip"
    else
        dialer_snapshot="null"
    fi

    if [ "$listener_source_type" = "github" ]; then
        listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" images.yaml)
        listener_snapshot="snapshots/$listener_commit.zip"
    else
        listener_snapshot="null"
    fi

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: $name
    dialer: $dialer
    listener: $listener
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    dialerSnapshot: $dialer_snapshot
    listenerSnapshot: $listener_snapshot
EOF
done

# Add empty ignored tests section (filtering done upfront, so no ignored tests tracked)
cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF

ignoredTests: []
EOF

# Cache the generated matrix
save_to_cache "$OUTPUT_DIR" "$cache_key" "$CACHE_DIR" "transport"

print_success "Generated test matrix with ${#tests[@]} tests"
