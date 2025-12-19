#!/bin/bash
# Generate test matrix from images.yaml with filtering support
# Outputs test-matrix.yaml with content-addressed caching
# 8D permutations: dialer × listener × transport × secureChannel × muxer × relay × dialer_router × listener_router

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
CLI_TEST_SELECT="${1:-}"
CLI_TEST_IGNORE="${2:-}"
CLI_RELAY_SELECT="${3:-}"
CLI_RELAY_IGNORE="${4:-}"
CLI_ROUTER_SELECT="${5:-}"
CLI_ROUTER_IGNORE="${6:-}"
DEBUG="${7:-false}"  # Optional: debug mode flag
FORCE_MATRIX_REBUILD="${8:-false}"  # Optional: force matrix rebuild
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

# Get all entity IDs for negation expansion
all_impl_ids=($(yq eval '.implementations[].id' images.yaml))
all_relay_ids=($(yq eval '.relays[].id' images.yaml))
all_router_ids=($(yq eval '.routers[].id' images.yaml))

# Use test select and ignore values from CLI arguments
TEST_SELECT="$CLI_TEST_SELECT"
TEST_IGNORE="$CLI_TEST_IGNORE"
RELAY_SELECT="$CLI_RELAY_SELECT"
RELAY_IGNORE="$CLI_RELAY_IGNORE"
ROUTER_SELECT="$CLI_ROUTER_SELECT"
ROUTER_IGNORE="$CLI_ROUTER_IGNORE"

echo ""
echo "╲ Test Matrix Generation"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Display filters (expansion will happen during filter_entity_list calls)
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

if [ -n "$RELAY_SELECT" ]; then
    echo "→ Relay select: $RELAY_SELECT"
else
    echo "→ No relay-select specified (will include all relays)"
fi

if [ -n "$RELAY_IGNORE" ]; then
    echo "→ Relay ignore: $RELAY_IGNORE"
else
    echo "→ No relay-ignore specified"
fi

if [ -n "$ROUTER_SELECT" ]; then
    echo "→ Router select: $ROUTER_SELECT"
else
    echo "→ No router-select specified (will include all routers)"
fi

if [ -n "$ROUTER_IGNORE" ]; then
    echo "→ Router ignore: $ROUTER_IGNORE"
else
    echo "→ No router-ignore specified"
fi

# Use TEST_RUN_KEY from parent (run.sh) if available
# Otherwise compute cache key from images.yaml + all filters + debug
if [ -n "${TEST_RUN_KEY:-}" ]; then
    cache_key="$TEST_RUN_KEY"
    echo "→ Using test run key: $cache_key"
else
    # Fallback for standalone execution
    cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "$RELAY_SELECT" "$RELAY_IGNORE" "$ROUTER_SELECT" "$ROUTER_IGNORE" "$DEBUG")
    echo "→ Computed cache key: ${cache_key:0:8}"
fi

# Check cache (with optional force rebuild)
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$OUTPUT_DIR" "$FORCE_MATRIX_REBUILD" "hole-punch"; then
    exit 0
fi

echo ""

# Filter all three entity types upfront using global filter_entity_list function
echo "→ Filtering implementations..."
mapfile -t filtered_impl_ids < <(filter_entity_list "implementations" "$TEST_SELECT" "$TEST_IGNORE")
echo "  ✓ Filtered to ${#filtered_impl_ids[@]} implementations"

echo "→ Filtering relays..."
mapfile -t filtered_relay_ids < <(filter_entity_list "relays" "$RELAY_SELECT" "$RELAY_IGNORE")
echo "  ✓ Filtered to ${#filtered_relay_ids[@]} relays"

echo "→ Filtering routers..."
mapfile -t filtered_router_ids < <(filter_entity_list "routers" "$ROUTER_SELECT" "$ROUTER_IGNORE")
echo "  ✓ Filtered to ${#filtered_router_ids[@]} routers"

echo ""

# Load implementation data only for filtered implementations
echo "→ Loading implementation data into memory..."
declare -A impl_transports    # impl_transports[linux]="tcp quic-v1"
declare -A impl_secure        # impl_secure[linux]="noise tls"
declare -A impl_muxers        # impl_muxers[linux]="yamux mplex"
declare -A impl_dial_only     # impl_dial_only[linux]="webtransport"

for impl_id in "${filtered_impl_ids[@]}"; do
    transports=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .transports | join(\" \")" images.yaml)
    secure=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .secureChannels | join(\" \")" images.yaml)
    muxers=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .muxers | join(\" \")" images.yaml)
    dial_only=$(yq eval ".implementations[] | select(.id == \"$impl_id\") | .dialOnly | join(\" \")" images.yaml 2>/dev/null || echo "")

    impl_transports["$impl_id"]="$transports"
    impl_secure["$impl_id"]="$secure"
    impl_muxers["$impl_id"]="$muxers"
    impl_dial_only["$impl_id"]="$dial_only"
done

echo "  ✓ Loaded data for ${#filtered_impl_ids[@]} filtered implementations"

# Initialize test lists
tests=()
test_num=0

# Check if a transport can be used with an implementation as listener
# Returns 0 (true) if transport can be used as listener, 1 (false) if dialOnly
can_be_listener_for_transport() {
    local impl_id="$1"
    local transport="$2"

    local dial_only_transports="${impl_dial_only[$impl_id]:-}"

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
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Iterate through FILTERED entities only (no inline filtering or ignore flags needed!)
for relay_id in "${filtered_relay_ids[@]}"; do
    for dialer_router_id in "${filtered_router_ids[@]}"; do
        for listener_router_id in "${filtered_router_ids[@]}"; do
            for dialer_id in "${filtered_impl_ids[@]}"; do
                dialer_transports="${impl_transports[$dialer_id]}"
                dialer_secure="${impl_secure[$dialer_id]}"
                dialer_muxers="${impl_muxers[$dialer_id]}"

                for listener_id in "${filtered_impl_ids[@]}"; do
                    # No filtering needed - all entities already filtered upfront!

                    listener_transports="${impl_transports[$listener_id]}"
                    listener_secure="${impl_secure[$listener_id]}"
                    listener_muxers="${impl_muxers[$listener_id]}"

                    # Find common transports
                    common_transports=$(get_common "$dialer_transports" "$listener_transports")

                    # Skip if no common transports
                    [ -z "$common_transports" ] && continue

                    # Process each common transport
                    for transport in $common_transports; do
                        # Check if LISTENER IMPLEMENTATION can handle this transport
                        if ! can_be_listener_for_transport "$listener_id" "$transport"; then
                            continue  # Skip: listener implementation has this transport in dialOnly
                        fi

                        if is_standalone_transport "$transport"; then
                            # Standalone transport (no secure/muxer needed)
                            test_name="$dialer_id x $listener_id ($transport) [dr: $dialer_router_id, rly: $relay_id, lr: $listener_router_id]"

                            # No filtering needed - all entities already filtered upfront
                            test_num=$((test_num + 1))
                            tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null|$relay_id|$dialer_router_id|$listener_router_id")
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
                                    test_name="$dialer_id x $listener_id ($transport, $secure, $muxer) [dr: $dialer_router_id, rly: $relay_id, lr: $listener_router_id]"

                                    # No filtering needed - all entities already filtered upfront
                                    test_num=$((test_num + 1))
                                    tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer|$relay_id|$dialer_router_id|$listener_router_id")
                                done
                            done
                        fi
                    done
                done
            done
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
  relaySelect: $RELAY_SELECT
  relayIgnore: $RELAY_IGNORE
  routerSelect: $ROUTER_SELECT
  routerIgnore: $ROUTER_IGNORE
  totalTests: ${#tests[@]}
  ignoredTests: 0
  debug: $DEBUG

tests:
EOF

for test in "${tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer relay_id dialer_router_id listener_router_id <<< "$test"

    # Get commits, treating null/empty as local
    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" images.yaml 2>/dev/null || echo "local")
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" images.yaml 2>/dev/null || echo "local")

    # Normalize null values to "local"
    [ "$dialer_commit" = "null" ] && dialer_commit="local"
    [ "$listener_commit" = "null" ] && listener_commit="local"

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: "$name"
    dialer: $dialer
    listener: $listener
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    dialerRouter: $dialer_router_id
    relay: $relay_id
    listenerRouter: $listener_router_id
EOF

    # Only add snapshot fields for non-local sources
    if [ "$dialer_commit" != "local" ]; then
        echo "    dialerSnapshot: snapshots/$dialer_commit.zip" >> "$OUTPUT_DIR/test-matrix.yaml"
    fi
    if [ "$listener_commit" != "local" ]; then
        echo "    listenerSnapshot: snapshots/$listener_commit.zip" >> "$OUTPUT_DIR/test-matrix.yaml"
    fi
done

# Add empty ignored tests section (filtering done upfront, so no ignored tests tracked)
cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF

ignoredTests: []
EOF

# Cache the generated matrix
save_to_cache "$OUTPUT_DIR" "$cache_key" "$CACHE_DIR" "hole-punch"

echo ""
echo "╲ ✓ Generated test matrix with ${#tests[@]} tests"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
