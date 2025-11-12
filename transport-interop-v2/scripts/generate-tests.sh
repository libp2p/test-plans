#!/bin/bash
# Generate test matrix from impls.yaml with 3D combinations (transport × secureChannel × muxer)
# Outputs test-matrix.yaml with content-addressed caching

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
CLI_TEST_FILTER="${1:-}"
CLI_TEST_IGNORE="${2:-}"
IMPL_PATH="${3:-}"  # Optional: impl path for loading defaults (e.g., "impls/rust")
DEBUG="${4:-false}"  # Optional: debug mode flag
OUTPUT_DIR="${TEST_PASS_DIR:-.}"  # Use TEST_PASS_DIR if set, otherwise current directory

# Standalone transports (don't require muxer/secureChannel)
STANDALONE_TRANSPORTS="quic quic-v1 webtransport webrtc webrtc-direct"

# Check if transport is standalone (doesn't need muxer/secureChannel)
is_standalone_transport() {
    local transport="$1"
    echo "$STANDALONE_TRANSPORTS" | grep -qw "$transport"
}

# Load test selection defaults from YAML files
load_test_filter_from_yaml() {
    local impl_path="$1"
    local selection_file

    if [ -n "$impl_path" ] && [ -f "$impl_path/test-selection.yaml" ]; then
        selection_file="$impl_path/test-selection.yaml"
    elif [ -f "test-selection.yaml" ]; then
        selection_file="test-selection.yaml"
    else
        echo ""
        return
    fi

    # Extract test-filter list (pipe-separated)
    local filter=$(yq eval '.test-filter[]' "$selection_file" 2>/dev/null | paste -sd'|' -)
    echo "$filter"
}

load_test_ignore_from_yaml() {
    local impl_path="$1"
    local selection_file

    if [ -n "$impl_path" ] && [ -f "$impl_path/test-selection.yaml" ]; then
        selection_file="$impl_path/test-selection.yaml"
    elif [ -f "test-selection.yaml" ]; then
        selection_file="test-selection.yaml"
    else
        echo ""
        return
    fi

    # Extract test-ignore list (pipe-separated)
    local ignore=$(yq eval '.test-ignore[]' "$selection_file" 2>/dev/null | paste -sd'|' -)
    echo "$ignore"
}

# Determine test filter and ignore values
# Priority: CLI args > YAML files
TEST_FILTER="$CLI_TEST_FILTER"
TEST_IGNORE="$CLI_TEST_IGNORE"

echo ""
echo "╲ Test Matrix Generation"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Load from YAML if not provided via CLI
if [ -z "$CLI_TEST_FILTER" ]; then
    YAML_FILTER=$(load_test_filter_from_yaml "$IMPL_PATH")
    if [ -n "$YAML_FILTER" ]; then
        TEST_FILTER="$YAML_FILTER"
        if [ -n "$IMPL_PATH" ]; then
            echo "→ Loaded test-filter from $IMPL_PATH/test-selection.yaml"
        else
            echo "→ Loaded test-filter from test-selection.yaml"
        fi
    else
        echo "→ No test-filter specified (will include all tests)"
    fi
else
    echo "→ Using CLI test-filter: $TEST_FILTER"
fi

if [ -z "$CLI_TEST_IGNORE" ]; then
    YAML_IGNORE=$(load_test_ignore_from_yaml "$IMPL_PATH")
    if [ -n "$YAML_IGNORE" ]; then
        TEST_IGNORE="$YAML_IGNORE"
        if [ -n "$IMPL_PATH" ]; then
            echo "→ Loaded test-ignore from $IMPL_PATH/test-selection.yaml"
        else
            echo "→ Loaded test-ignore from test-selection.yaml"
        fi
    else
        echo "→ No test-ignore specified"
    fi
else
    echo "→ Using CLI test-ignore: $TEST_IGNORE"
fi

# Compute cache key from impls.yaml + all test-selection.yaml files + filter + ignore
cache_key=$({ cat impls.yaml impls/*/test-selection.yaml test-selection.yaml 2>/dev/null; echo "$TEST_FILTER||$TEST_IGNORE||$DEBUG"; } | sha256sum | cut -d' ' -f1)
echo "→ Computed cache key: ${cache_key:0:8}"

cache_file="$CACHE_DIR/test-matrix/${cache_key}.yaml"

# Check cache
if [ -f "$cache_file" ]; then
    echo "  ✓ [HIT] Using cached test matrix: ${cache_key:0:8}.yaml"
    cp "$cache_file" "$OUTPUT_DIR/test-matrix.yaml"

    # Show cached test count
    test_count=$(yq eval '.metadata.totalTests' "$OUTPUT_DIR/test-matrix.yaml")
    echo "  ✓ Loaded $test_count tests from cache"
    exit 0
fi

echo "  → [MISS] Generating new test matrix"
mkdir -p "$CACHE_DIR/test-matrix"
echo ""

# Read all implementations
impl_count=$(yq eval '.implementations | length' impls.yaml)
echo "→ Found $impl_count implementations in impls.yaml"

# Declare associative arrays for O(1) lookups
declare -A impl_transports    # impl_transports[rust-v0.56]="tcp ws quic-v1"
declare -A impl_secure        # impl_secure[rust-v0.56]="tls noise"
declare -A impl_muxers        # impl_muxers[rust-v0.56]="yamux mplex"
declare -a impl_ids           # impl_ids=(rust-v0.56 rust-v0.55 ...)

# Load all implementation data using yq
echo "→ Loading implementation data into memory..."
for ((i=0; i<impl_count; i++)); do
    id=$(yq eval ".implementations[$i].id" impls.yaml)
    transports=$(yq eval ".implementations[$i].transports | join(\" \")" impls.yaml)
    secure=$(yq eval ".implementations[$i].secureChannels | join(\" \")" impls.yaml)
    muxers=$(yq eval ".implementations[$i].muxers | join(\" \")" impls.yaml)

    impl_ids+=("$id")
    impl_transports["$id"]="$transports"
    impl_secure["$id"]="$secure"
    impl_muxers["$id"]="$muxers"
done

echo "  ✓ Loaded ${#impl_ids[@]} implementations into memory"

# Pre-parse filter and ignore patterns once
# Always declare arrays (even if empty) to avoid unbound variable errors
declare -a FILTER_PATTERNS=()
declare -a IGNORE_PATTERNS=()

if [ -n "$TEST_FILTER" ]; then
    IFS='|' read -ra FILTER_PATTERNS <<< "$TEST_FILTER"
    echo "  ✓ Loaded ${#FILTER_PATTERNS[@]} filter patterns"
fi

if [ -n "$TEST_IGNORE" ]; then
    IFS='|' read -ra IGNORE_PATTERNS <<< "$TEST_IGNORE"
    echo "  ✓ Loaded ${#IGNORE_PATTERNS[@]} ignore patterns"
fi

# Helper function to check if test name matches filter
matches_filter() {
    local test_name="$1"

    # No filter = match all
    [ ${#FILTER_PATTERNS[@]} -eq 0 ] && return 0

    # Check each filter pattern
    for filter in "${FILTER_PATTERNS[@]}"; do
        [[ "$test_name" == *"$filter"* ]] && return 0
    done

    return 1
}

# Helper function to check if test name should be ignored
should_ignore() {
    local test_name="$1"

    # No ignore patterns = don't ignore
    [ ${#IGNORE_PATTERNS[@]} -eq 0 ] && return 1

    # Check each ignore pattern
    for ignore in "${IGNORE_PATTERNS[@]}"; do
        [[ "$test_name" == *"$ignore"* ]] && return 0
    done

    return 1
}

# Get common elements between two space-separated lists
get_common() {
    local list1="$1"
    local list2="$2"
    local result=""

    for item in $list1; do
        if [[ " $list2 " == *" $item "* ]]; then
            result="$result $item"
        fi
    done

    echo "$result"
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
        listener_transports="${impl_transports[$listener_id]}"
        listener_secure="${impl_secure[$listener_id]}"
        listener_muxers="${impl_muxers[$listener_id]}"

        # Find common transports (much faster than grep)
        common_transports=$(get_common "$dialer_transports" "$listener_transports")

        # Skip if no common transports
        [ -z "$common_transports" ] && continue

        # Process each common transport
        for transport in $common_transports; do

            if is_standalone_transport "$transport"; then
                # Standalone transport
                test_name="$dialer_id x $listener_id ($transport)"

                # Check filter/ignore (using pre-parsed functions)
                if matches_filter "$test_name"; then
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

                        # Check filter/ignore (using pre-parsed functions)
                        if matches_filter "$test_name"; then
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
  filter: $(echo "$TEST_FILTER" | sed 's/|/, /g')
  ignore: $(echo "$TEST_IGNORE" | sed 's/|/, /g')
  totalTests: ${#tests[@]}
  ignoredTests: ${#ignored_tests[@]}
  debug: $DEBUG

tests:
EOF

for test in "${tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer <<< "$test"

    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml)
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml)

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: $name
    dialer: $dialer
    listener: $listener
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    dialerSnapshot: snapshots/$dialer_commit.zip
    listenerSnapshot: snapshots/$listener_commit.zip
EOF
done

# Add ignored tests section
cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF

ignoredTests:
EOF

for test in "${ignored_tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer <<< "$test"

    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml)
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml)

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: $name
    dialer: $dialer
    listener: $listener
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    dialerSnapshot: snapshots/$dialer_commit.zip
    listenerSnapshot: snapshots/$listener_commit.zip
EOF
done

# Cache the generated matrix
cp "$OUTPUT_DIR/test-matrix.yaml" "$cache_file"

echo "╲ ✓ Generated test matrix with ${#tests[@]} tests (${#ignored_tests[@]} ignored)"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "✓ Cached as: ${cache_key:0:8}.yaml"
