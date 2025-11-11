#!/bin/bash
# Generate test matrix from impls.yaml with 3D combinations (transport × secureChannel × muxer)
# Outputs test-matrix.yaml with content-addressed caching

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
CLI_TEST_FILTER="${1:-}"
CLI_TEST_IGNORE="${2:-}"
IMPL_PATH="${3:-}"  # Optional: impl path for loading defaults (e.g., "impls/rust")
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

echo ""
echo "Filter settings:"
echo "  test-filter: ${TEST_FILTER:-<all>}"
echo "  test-ignore: ${TEST_IGNORE:-<none>}"
echo ""

# Compute cache key from impls.yaml + all test-selection.yaml files + filter + ignore
echo "→ Computing cache key..."
cache_key=$({ cat impls.yaml impls/*/test-selection.yaml test-selection.yaml 2>/dev/null; echo "$TEST_FILTER|$TEST_IGNORE"; } | sha256sum | cut -d' ' -f1)
echo "→ Cache key computed: ${cache_key:0:8}"

cache_file="$CACHE_DIR/test-matrix/${cache_key}.yaml"

# Check cache
if [ -f "$cache_file" ]; then
    echo "→ Using cached test matrix: ${cache_key:0:8}.yaml"
    cp "$cache_file" "$OUTPUT_DIR/test-matrix.yaml"

    # Show cached test count
    test_count=$(yq eval '.metadata.totalTests' "$OUTPUT_DIR/test-matrix.yaml")
    echo ""
    echo "✓ Loaded $test_count tests from cache"
    exit 0
fi

echo "→ Generating new test matrix (cache miss)"
mkdir -p "$CACHE_DIR/test-matrix"
echo ""

# Read all implementations
impl_count=$(yq eval '.implementations | length' impls.yaml)
echo "→ Found $impl_count implementations in impls.yaml"
echo ""

# Initialize test lists
tests=()
ignored_tests=()
test_num=0

echo "╲ Considering test combinations:"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

# Generate all combinations (3D matrix)
for ((i=0; i<impl_count; i++)); do
    dialer_id=$(yq eval ".implementations[$i].id" impls.yaml)
    dialer_transports=$(yq eval ".implementations[$i].transports[]" impls.yaml 2>/dev/null)
    dialer_secure=$(yq eval ".implementations[$i].secureChannels[]" impls.yaml 2>/dev/null)
    dialer_muxers=$(yq eval ".implementations[$i].muxers[]" impls.yaml 2>/dev/null)

    for ((j=0; j<impl_count; j++)); do
        listener_id=$(yq eval ".implementations[$j].id" impls.yaml)
        listener_transports=$(yq eval ".implementations[$j].transports[]" impls.yaml 2>/dev/null)
        listener_secure=$(yq eval ".implementations[$j].secureChannels[]" impls.yaml 2>/dev/null)
        listener_muxers=$(yq eval ".implementations[$j].muxers[]" impls.yaml 2>/dev/null)

        # Find common transports
        for transport in $dialer_transports; do
            if echo "$listener_transports" | grep -q "^${transport}$"; then

                # Check if standalone transport
                if is_standalone_transport "$transport"; then
                    # Standalone: no muxer/secure needed
                    test_name="$dialer_id x $listener_id ($transport)"

                    # Apply filter (if any)
                    if [ -n "$TEST_FILTER" ]; then
                        match=false
                        IFS='|' read -ra FILTERS <<< "$TEST_FILTER"
                        for filter in "${FILTERS[@]}"; do
                            if [[ "$test_name" == *"$filter"* ]]; then
                                match=true
                                break
                            fi
                        done
                        if [ "$match" = false ]; then
                            continue
                        fi
                    fi

                    # Apply ignore (if any)
                    if [ -n "$TEST_IGNORE" ]; then
                        skip=false
                        IFS='|' read -ra IGNORES <<< "$TEST_IGNORE"
                        for ignore in "${IGNORES[@]}"; do
                            if [[ "$test_name" == *"$ignore"* ]]; then
                                skip=true
                                break
                            fi
                        done
                        if [ "$skip" = true ]; then
                            # Add to ignored tests list
                            ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null")
                            continue
                        fi
                    fi

                    # Add test (standalone)
                    test_num=$((test_num + 1))
                    echo "  [$test_num] ✓ $test_name"
                    tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null")

                else
                    # Non-standalone: need secure channel + muxer combinations
                    for secure in $dialer_secure; do
                        if echo "$listener_secure" | grep -q "^${secure}$"; then

                            for muxer in $dialer_muxers; do
                                if echo "$listener_muxers" | grep -q "^${muxer}$"; then

                                    test_name="$dialer_id x $listener_id ($transport, $secure, $muxer)"

                                    # Apply filter (if any)
                                    if [ -n "$TEST_FILTER" ]; then
                                        match=false
                                        IFS='|' read -ra FILTERS <<< "$TEST_FILTER"
                                        for filter in "${FILTERS[@]}"; do
                                            if [[ "$test_name" == *"$filter"* ]]; then
                                                match=true
                                                break
                                            fi
                                        done
                                        if [ "$match" = false ]; then
                                            continue
                                        fi
                                    fi

                                    # Apply ignore (if any)
                                    if [ -n "$TEST_IGNORE" ]; then
                                        skip=false
                                        IFS='|' read -ra IGNORES <<< "$TEST_IGNORE"
                                        for ignore in "${IGNORES[@]}"; do
                                            if [[ "$test_name" == *"$ignore"* ]]; then
                                                skip=true
                                                break
                                            fi
                                        done
                                        if [ "$skip" = true ]; then
                                            # Add to ignored tests list
                                            ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer")
                                            continue
                                        fi
                                    fi

                                    # Add test (3D combination)
                                    test_num=$((test_num + 1))
                                    echo "  [$test_num] ✓ $test_name"
                                    tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer")
                                fi
                            done
                        fi
                    done
                fi
            fi
        done
    done
done

echo ""

# Generate test-matrix.yaml
cat > "$OUTPUT_DIR/test-matrix.yaml" <<EOF
metadata:
  generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  filter: $(echo "$TEST_FILTER" | sed 's/|/, /g')
  ignore: $(echo "$TEST_IGNORE" | sed 's/|/, /g')
  totalTests: ${#tests[@]}
  ignoredTests: ${#ignored_tests[@]}

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
echo "  Cached as: ${cache_key:0:8}.yaml"
