#!/bin/bash
# Generate test matrix from impls.yaml with 3D combinations (transport × secureChannel × muxer)
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

# Display and expand test selection
if [ -n "$TEST_SELECT" ]; then
    echo "→ Test select: $TEST_SELECT"
    ORIGINAL_SELECT="$TEST_SELECT"
    TEST_SELECT=$(expand_all_patterns "$TEST_SELECT" "impls.yaml")
    # Always show final expanded value
    echo "  → Expanded to: $TEST_SELECT"
else
    echo "→ No test-select specified (will include all tests)"
fi

# Display and expand test ignore
if [ -n "$TEST_IGNORE" ]; then
    echo "→ Test ignore: $TEST_IGNORE"
    ORIGINAL_IGNORE="$TEST_IGNORE"
    TEST_IGNORE=$(expand_all_patterns "$TEST_IGNORE" "impls.yaml")
    # Always show final expanded value
    echo "  → Expanded to: $TEST_IGNORE"
else
    echo "→ No test-ignore specified"
fi

# Compute cache key from impls.yaml + select + ignore + debug
# Pass empty strings for relay/router params (not used by transport tests)
cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "" "" "" "" "$DEBUG")
echo "→ Computed cache key: ${cache_key:0:8}"

# Check cache (with optional force rebuild)
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$OUTPUT_DIR" "$FORCE_MATRIX_REBUILD"; then
    exit 0
fi

echo ""

# Read all implementations
impl_count=$(yq eval '.implementations | length' impls.yaml)
echo "→ Found $impl_count implementations in impls.yaml"

# Declare associative arrays for O(1) lookups
declare -A impl_transports    # impl_transports[rust-v0.56]="tcp ws quic-v1"
declare -A impl_secure        # impl_secure[rust-v0.56]="tls noise"
declare -A impl_muxers        # impl_muxers[rust-v0.56]="yamux mplex"
declare -A impl_dial_only     # impl_dial_only[chromium-rust-v0.54]="webtransport webrtc-direct ws"
declare -a impl_ids           # impl_ids=(rust-v0.56 rust-v0.55 ...)

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

# Pre-parse select and ignore patterns once
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

# Initialize test lists
tests=()
ignored_tests=()
test_num=0

# Iterate through all dialer/listener pairs using pre-loaded data
for dialer_id in "${impl_ids[@]}"; do
    dialer_transports="${impl_transports[$dialer_id]}"
    dialer_secure="${impl_secure[$dialer_id]}"
    dialer_muxers="${impl_muxers[$dialer_id]}"

    for listener_id in "${impl_ids[@]}"; do
        # When TEST_SELECT is specified, include test if EITHER dialer OR listener matches
        if [ ${#SELECT_PATTERNS[@]} -gt 0 ]; then
            impl_matches_select "$dialer_id" || impl_matches_select "$listener_id" || continue
        fi

        listener_transports="${impl_transports[$listener_id]}"
        listener_secure="${impl_secure[$listener_id]}"
        listener_muxers="${impl_muxers[$listener_id]}"

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

                # Check select/ignore (using pre-parsed functions)
                if matches_select "$test_name"; then
                    if should_ignore "$test_name"; then
                        ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null")
                    else
                        test_num=$((test_num + 1))
                        tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null")
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
                        test_name="$dialer_id x $listener_id ($transport, $secure, $muxer)"

                        # Check select/ignore (using pre-parsed functions)
                        if matches_select "$test_name"; then
                            if should_ignore "$test_name"; then
                                ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer")
                            else
                                test_num=$((test_num + 1))
                                tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer")
                            fi
                        fi
                    done
                done
            fi
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
    IFS='|' read -r name dialer listener transport secure muxer <<< "$test"

    # Get source types and commits (only for github-type implementations)
    dialer_source_type=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.type" impls.yaml)
    listener_source_type=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.type" impls.yaml)

    # Only get commits for github-type sources
    if [ "$dialer_source_type" = "github" ]; then
        dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml)
        dialer_snapshot="snapshots/$dialer_commit.zip"
    else
        dialer_snapshot="null"
    fi

    if [ "$listener_source_type" = "github" ]; then
        listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml)
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

# Add ignored tests section
cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF

ignoredTests:
EOF

for test in "${ignored_tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer <<< "$test"

    # Get source types and commits (only for github-type implementations)
    dialer_source_type=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.type" impls.yaml)
    listener_source_type=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.type" impls.yaml)

    # Only get commits for github-type sources
    if [ "$dialer_source_type" = "github" ]; then
        dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml)
        dialer_snapshot="snapshots/$dialer_commit.zip"
    else
        dialer_snapshot="null"
    fi

    if [ "$listener_source_type" = "github" ]; then
        listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml)
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

# Cache the generated matrix
save_to_cache "$OUTPUT_DIR" "$cache_key" "$CACHE_DIR"

echo "╲ ✓ Generated test matrix with ${#tests[@]} tests (${#ignored_tests[@]} ignored)"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
