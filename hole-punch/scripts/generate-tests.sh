#!/bin/bash
# Generate test matrix from impls.yaml with filtering support
# Outputs test-matrix.yaml with content-addressed caching
# 8D permutations: dialer × listener × transport × secureChannel × muxer × relay × dialer_router × listener_router

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
CLI_TEST_SELECT="${1:-}"
CLI_TEST_IGNORE="${2:-}"
DEBUG="${3:-false}"  # Optional: debug mode flag
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
source "$SCRIPT_DIR/../../scripts/lib-test-aliases.sh"
source "$SCRIPT_DIR/../../scripts/lib-test-filtering.sh"
source "$SCRIPT_DIR/../../scripts/lib-test-caching.sh"

# Load test aliases from impls.yaml
load_aliases

# Use test select and ignore values from CLI arguments
TEST_SELECT="$CLI_TEST_SELECT"
TEST_IGNORE="$CLI_TEST_IGNORE"

echo ""
echo "╲ Test Matrix Generation"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Display test selection
if [ -n "$TEST_SELECT" ]; then
    echo "→ Test select: $TEST_SELECT"
else
    echo "→ No test-select specified (will include all tests)"
fi

# Expand aliases in TEST_SELECT
if [ -n "$TEST_SELECT" ]; then
    ORIGINAL_SELECT="$TEST_SELECT"
    TEST_SELECT=$(expand_aliases "$TEST_SELECT")
    if [ "$TEST_SELECT" != "$ORIGINAL_SELECT" ]; then
        echo "  → Expanded aliases to: $TEST_SELECT"
    fi
fi

# Display test ignore
if [ -n "$TEST_IGNORE" ]; then
    echo "→ Test ignore: $TEST_IGNORE"
else
    echo "→ No test-ignore specified"
fi

# Expand aliases in TEST_IGNORE
if [ -n "$TEST_IGNORE" ]; then
    ORIGINAL_IGNORE="$TEST_IGNORE"
    TEST_IGNORE=$(expand_aliases "$TEST_IGNORE")
    if [ "$TEST_IGNORE" != "$ORIGINAL_IGNORE" ]; then
        echo "  → Expanded aliases to: $TEST_IGNORE"
    fi
fi

# Compute cache key from impls.yaml + select + ignore + debug
cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "$DEBUG")
echo "→ Computed cache key: ${cache_key:0:8}"

# Check cache
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$OUTPUT_DIR"; then
    exit 0
fi

echo ""

# Read all implementations
impl_count=$(yq eval '.implementations | length' impls.yaml)
echo "→ Found $impl_count implementations in impls.yaml"

# Read all relay types
relay_count=$(yq eval '.relays | length' impls.yaml)
echo "→ Found $relay_count relay types in impls.yaml"

# Read all router types
router_count=$(yq eval '.routers | length' impls.yaml)
echo "→ Found $router_count router types in impls.yaml"

# Declare associative arrays for O(1) lookups
declare -A impl_transports    # impl_transports[linux]="tcp quic-v1"
declare -A impl_secure        # impl_secure[linux]="noise tls"
declare -A impl_muxers        # impl_muxers[linux]="yamux mplex"
declare -A impl_dial_only     # impl_dial_only[linux]="webtransport"
declare -a impl_ids           # impl_ids=(linux ...)
declare -a relay_ids          # relay_ids=(linux ...)
declare -a router_ids         # router_ids=(linux ...)

# Load all implementation data using yq
echo "→ Loading implementation data into memory..."
for ((i=0; i<impl_count; i++)); do
    id=$(yq eval ".implementations[$i].id" impls.yaml)
    transports=$(yq eval ".implementations[$i].transports | join(\" \")" impls.yaml)
    secure=$(yq eval ".implementations[$i].secureChannels | join(\" \")" impls.yaml)
    muxers=$(yq eval ".implementations[$i].muxers | join(\" \")" impls.yaml)
    dial_only=$(yq eval ".implementations[$i].dialOnly | join(\" \")" impls.yaml 2>/dev/null || echo "")

    impl_ids+=("$id")
    impl_transports["$id"]="$transports"
    impl_secure["$id"]="$secure"
    impl_muxers["$id"]="$muxers"
    impl_dial_only["$id"]="$dial_only"
done

echo "  ✓ Loaded ${#impl_ids[@]} implementations into memory"

# Load all relay types using yq
echo "→ Loading relay types into memory..."
for ((i=0; i<relay_count; i++)); do
    relay_id=$(yq eval ".relays[$i].id" impls.yaml)
    relay_ids+=("$relay_id")
done

echo "  ✓ Loaded ${#relay_ids[@]} relay types into memory"

# Load all router types using yq
echo "→ Loading router types into memory..."
for ((i=0; i<router_count; i++)); do
    router_id=$(yq eval ".routers[$i].id" impls.yaml)
    router_ids+=("$router_id")
done

echo "  ✓ Loaded ${#router_ids[@]} router types into memory"

# Initialize test lists
tests=()
ignored_tests=()
test_num=0

# Always declare arrays (even if empty) to avoid unbound variable errors
declare -a SELECT_PATTERNS=()
declare -a IGNORE_PATTERNS=()

if [ -n "$TEST_SELECT" ]; then
    IFS='|' read -ra SELECT_PATTERNS <<< "$TEST_SELECT"
    echo "  ✓ Loaded ${#SELECT_PATTERNS[@]} select patterns"
fi

if [ -n "$TEST_IGNORE" ]; then
    IFS='|' read -ra IGNORE_PATTERNS <<< "$TEST_IGNORE"
    echo "  ✓ Loaded ${#IGNORE_PATTERNS[@]} ignore patterns"
fi

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

# Iterate through all relay, router, and implementation combinations
for relay_id in "${relay_ids[@]}"; do
    for dialer_router_id in "${router_ids[@]}"; do
        for listener_router_id in "${router_ids[@]}"; do
            for dialer_id in "${impl_ids[@]}"; do
                # Skip if dialer doesn't match select filter
                impl_matches_select "$dialer_id" || continue

                dialer_transports="${impl_transports[$dialer_id]}"
                dialer_secure="${impl_secure[$dialer_id]}"
                dialer_muxers="${impl_muxers[$dialer_id]}"

                for listener_id in "${impl_ids[@]}"; do
                    # Skip if listener doesn't match select filter
                    impl_matches_select "$listener_id" || continue

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
                            test_name="$dialer_id x $listener_id ($transport) [$dialer_router_id] - [$relay_id] - [$listener_router_id]"

                            # Check select/ignore
                            if matches_select "$test_name"; then
                                if should_ignore "$test_name"; then
                                    ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null|$relay_id|$dialer_router_id|$listener_router_id")
                                else
                                    test_num=$((test_num + 1))
                                    tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null|$relay_id|$dialer_router_id|$listener_router_id")
                                fi
                            fi
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
                                    test_name="$dialer_id x $listener_id ($transport, $secure, $muxer) [$dialer_router_id] - [$relay_id] - [$listener_router_id]"

                                    # Check select/ignore
                                    if matches_select "$test_name"; then
                                        if should_ignore "$test_name"; then
                                            ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer|$relay_id|$dialer_router_id|$listener_router_id")
                                        else
                                            test_num=$((test_num + 1))
                                            tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer|$relay_id|$dialer_router_id|$listener_router_id")
                                        fi
                                    fi
                                done
                            done
                        fi
                    done
                done
            done
        done
    done
done

echo "✓ Generated ${#tests[@]} tests (${#ignored_tests[@]} ignored)"

echo ""

# Generate test-matrix.yaml
cat > "$OUTPUT_DIR/test-matrix.yaml" <<EOF
metadata:
  generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  select: $(echo "$TEST_SELECT" | sed 's/|/, /g')
  ignore: $(echo "$TEST_IGNORE" | sed 's/|/, /g')
  totalTests: ${#tests[@]}
  ignoredTests: ${#ignored_tests[@]}
  debug: $DEBUG

tests:
EOF

for test in "${tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer relay_id dialer_router_id listener_router_id <<< "$test"

    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml 2>/dev/null || echo "local")
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml 2>/dev/null || echo "local")

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: $name
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

# Add ignored tests section
cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF

ignoredTests:
EOF

for test in "${ignored_tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer relay_id dialer_router_id listener_router_id <<< "$test"

    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml 2>/dev/null || echo "local")
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml 2>/dev/null || echo "local")

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: $name
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

# Cache the generated matrix
save_to_cache "$OUTPUT_DIR" "$cache_key" "$CACHE_DIR"

echo ""
echo "╲ ✓ Generated test matrix with ${#tests[@]} tests (${#ignored_tests[@]} ignored)"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
