#!/bin/bash
# Generate test matrix from impls.yaml with filtering support
# Outputs test-matrix.yaml with content-addressed caching

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
CLI_TEST_SELECT="${1:-}"
CLI_TEST_IGNORE="${2:-}"
DEBUG="${3:-false}"  # Optional: debug mode flag
OUTPUT_DIR="${TEST_PASS_DIR:-.}"  # Use TEST_PASS_DIR if set, otherwise current directory

# Load aliases from impls.yaml into an associative array
load_aliases() {
    declare -gA ALIASES  # Global associative array

    if [ ! -f "impls.yaml" ]; then
        return
    fi

    # Check if test-aliases exists
    local alias_count=$(yq eval '.test-aliases | length' impls.yaml 2>/dev/null || echo 0)

    if [ "$alias_count" -eq 0 ] || [ "$alias_count" = "null" ]; then
        return
    fi

    # Load each alias
    for ((i=0; i<alias_count; i++)); do
        local alias_name=$(yq eval ".test-aliases[$i].alias" impls.yaml)
        local alias_value=$(yq eval ".test-aliases[$i].value" impls.yaml)
        ALIASES["$alias_name"]="$alias_value"
    done
}

# Get all implementation IDs as a pipe-separated string
get_all_impl_ids() {
    yq eval '.implementations[].id' impls.yaml | paste -sd'|' -
}

# Expand a single negated alias (!~alias)
# Returns the expanded value (all impl IDs that DON'T match the alias value)
expand_negated_alias() {
    local alias_name="$1"

    # Get the alias value
    if [ -z "${ALIASES[$alias_name]:-}" ]; then
        echo ""
        return
    fi

    local alias_value="${ALIASES[$alias_name]}"

    # Get all implementation IDs
    local all_impls=$(get_all_impl_ids)

    # Split alias value by | to get patterns to exclude
    IFS='|' read -ra EXCLUDE_PATTERNS <<< "$alias_value"

    # Split all impl IDs by |
    IFS='|' read -ra ALL_IDS <<< "$all_impls"

    # Filter: keep IDs that DON'T match any exclude pattern
    local result=""
    for impl_id in "${ALL_IDS[@]}"; do
        local should_exclude=false

        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            if [[ "$impl_id" == *"$pattern"* ]]; then
                should_exclude=true
                break
            fi
        done

        if [ "$should_exclude" = false ]; then
            if [ -z "$result" ]; then
                result="$impl_id"
            else
                result="$result|$impl_id"
            fi
        fi
    done

    echo "$result"
}

# Expand aliases in a test selection string
# Handles both ~alias and !~alias syntax
expand_aliases() {
    local input="$1"

    # If empty, return empty
    if [ -z "$input" ]; then
        echo ""
        return
    fi

    local result="$input"

    # Process negated aliases first (!~alias)
    while [[ "$result" =~ \!~([a-zA-Z0-9_-]+) ]]; do
        local alias_name="${BASH_REMATCH[1]}"
        local expanded=$(expand_negated_alias "$alias_name")

        if [ -n "$expanded" ]; then
            # Replace !~alias with expanded value
            result="${result//!~$alias_name/$expanded}"
        else
            # Unknown alias, remove it
            result="${result//!~$alias_name/}"
        fi
    done

    # Process regular aliases (~alias)
    while [[ "$result" =~ ~([a-zA-Z0-9_-]+) ]]; do
        local alias_name="${BASH_REMATCH[1]}"

        if [ -n "${ALIASES[$alias_name]:-}" ]; then
            local alias_value="${ALIASES[$alias_name]}"
            # Replace ~alias with its value
            result="${result//~$alias_name/$alias_value}"
        else
            # Unknown alias, remove it
            result="${result//~$alias_name/}"
        fi
    done

    # Clean up any double pipes or leading/trailing pipes
    result=$(echo "$result" | sed 's/||*/|/g' | sed 's/^|//; s/|$//')

    echo "$result"
}

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
cache_key=$({ cat impls.yaml 2>/dev/null; echo "$TEST_SELECT||$TEST_IGNORE||$DEBUG"; } | sha256sum | cut -d' ' -f1)
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

# Read all relay types
relay_count=$(yq eval '.relays | length' impls.yaml)
echo "→ Found $relay_count relay types in impls.yaml"

# Read all router types
router_count=$(yq eval '.routers | length' impls.yaml)
echo "→ Found $router_count router types in impls.yaml"

# Declare associative arrays for O(1) lookups
declare -A impl_transports    # impl_transports[linux]="tcp"
declare -a impl_ids           # impl_ids=(linux ...)
declare -a relay_ids          # relay_ids=(linux ...)
declare -a router_ids         # router_ids=(linux ...)

# Load all implementation data using yq
echo "→ Loading implementation data into memory..."
for ((i=0; i<impl_count; i++)); do
    id=$(yq eval ".implementations[$i].id" impls.yaml)
    transports=$(yq eval ".implementations[$i].transports | join(\" \")" impls.yaml)

    impl_ids+=("$id")
    impl_transports["$id"]="$transports"
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

# Helper function to check if test name matches select
matches_select() {
    local test_name="$1"

    # No select = match all
    [ ${#SELECT_PATTERNS[@]} -eq 0 ] && return 0

    # Check each select pattern
    for select in "${SELECT_PATTERNS[@]}"; do
        [[ "$test_name" == *"$select"* ]] && return 0
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

# Iterate through all relay, router, and implementation combinations
for relay_id in "${relay_ids[@]}"; do
    for router_id in "${router_ids[@]}"; do
        for dialer_id in "${impl_ids[@]}"; do
            dialer_transports="${impl_transports[$dialer_id]}"

            for listener_id in "${impl_ids[@]}"; do
                listener_transports="${impl_transports[$listener_id]}"

                # Find common transports (much faster than grep)
                common_transports=$(get_common "$dialer_transports" "$listener_transports")

                # Skip if no common transports
                [ -z "$common_transports" ] && continue

                # Process each common transport
                for transport in $common_transports; do
                    # Test name format: peer x peer (transport) [dialer-router] - [relay] - [listener-router]
                    test_name="$dialer_id x $listener_id ($transport) [$router_id] - [$relay_id] - [$router_id]"

                    # Check select/ignore (using pre-parsed functions)
                    if matches_select "$test_name"; then
                        if should_ignore "$test_name"; then
                            ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|$relay_id|$router_id")
                        else
                            test_num=$((test_num + 1))
                            tests+=("$test_name|$dialer_id|$listener_id|$transport|$relay_id|$router_id")
                        fi
                    fi
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
    IFS='|' read -r name dialer listener transport relay_id router_id <<< "$test"

    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml)
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml)

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: $name
    dialer: $dialer
    listener: $listener
    transport: $transport
    dialerRouter: $router_id
    relay: $relay_id
    listenerRouter: $router_id
    dialerSnapshot: snapshots/$dialer_commit.zip
    listenerSnapshot: snapshots/$listener_commit.zip
EOF
done

# Add ignored tests section
cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF

ignoredTests:
EOF

for test in "${ignored_tests[@]}"; do
    IFS='|' read -r name dialer listener transport relay_id router_id <<< "$test"

    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml)
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml)

    cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: $name
    dialer: $dialer
    listener: $listener
    transport: $transport
    dialerRouter: $router_id
    relay: $relay_id
    listenerRouter: $router_id
    dialerSnapshot: snapshots/$dialer_commit.zip
    listenerSnapshot: snapshots/$listener_commit.zip
EOF
done

# Cache the generated matrix
cp "$OUTPUT_DIR/test-matrix.yaml" "$cache_file"

echo "╲ ✓ Generated test matrix with ${#tests[@]} tests (${#ignored_tests[@]} ignored)"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
echo "✓ Cached as: ${cache_key:0:8}.yaml"
