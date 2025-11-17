#!/bin/bash
# Generate test matrix from impls.yaml with filtering support
# Outputs test-matrix.yaml with content-addressed caching

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_FILTER="${1:-}"
TEST_IGNORE="${2:-}"
IMPL_PATH="${3:-}"  # Optional: impl path for loading defaults

# Load test selection defaults from YAML files
load_test_selection() {
    local impl_path="$1"
    local selection_file

    if [ -n "$impl_path" ] && [ -f "$impl_path/test-selection.yaml" ]; then
        selection_file="$impl_path/test-selection.yaml"
    elif [ -f "test-selection.yaml" ]; then
        selection_file="test-selection.yaml"
    else
        echo "|"  # Empty filter and ignore
        return
    fi

    # Extract test-filter list (pipe-separated)
    local filter=$(yq eval '.test-filter | join("|")' "$selection_file")
    # Extract test-ignore list (pipe-separated)
    local ignore=$(yq eval '.test-ignore | join("|")' "$selection_file")

    echo "$filter|$ignore"
}

# If filter/ignore not provided via CLI, load from test-selection.yaml
if [ -z "$TEST_FILTER" ] && [ -z "$TEST_IGNORE" ]; then
    defaults=$(load_test_selection "$IMPL_PATH")
    TEST_FILTER=$(echo "$defaults" | cut -d'|' -f1)
    TEST_IGNORE=$(echo "$defaults" | cut -d'|' -f2)

    if [ -n "$IMPL_PATH" ]; then
        echo "Loaded test selection from $IMPL_PATH/test-selection.yaml"
    else
        echo "Loaded test selection from test-selection.yaml"
    fi
    echo "  Filter: ${TEST_FILTER:-<all>}"
    echo "  Ignore: ${TEST_IGNORE:-<none>}"
    echo ""
fi

# Compute cache key from impls.yaml + all test-selection.yaml files + filter + ignore
cache_key=$(cat impls.yaml impls/*/test-selection.yaml test-selection.yaml 2>/dev/null | \
    echo "$TEST_FILTER|$TEST_IGNORE" | \
    sha256sum | cut -d' ' -f1)

cache_file="$CACHE_DIR/test-matrix/${cache_key}.yaml"

# Check cache
if [ -f "$cache_file" ]; then
    echo "Using cached test matrix: ${cache_key:0:8}.yaml"
    cp "$cache_file" test-matrix.yaml
    exit 0
fi

echo "Generating new test matrix..."
mkdir -p "$CACHE_DIR/test-matrix"

# Read all implementations
impl_count=$(yq eval '.implementations | length' impls.yaml)

# Initialize test list
tests=()

# Generate all combinations
for ((i=0; i<impl_count; i++)); do
    dialer_id=$(yq eval ".implementations[$i].id" impls.yaml)
    dialer_transports=$(yq eval ".implementations[$i].transports[]" impls.yaml)

    for ((j=0; j<impl_count; j++)); do
        listener_id=$(yq eval ".implementations[$j].id" impls.yaml)
        listener_transports=$(yq eval ".implementations[$j].transports[]" impls.yaml)

        # Find common transports
        for transport in $dialer_transports; do
            if echo "$listener_transports" | grep -q "^${transport}$"; then
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
                        continue
                    fi
                fi

                # Add test
                tests+=("$test_name|$dialer_id|$listener_id|$transport")
            fi
        done
    done
done

# Generate test-matrix.yaml
cat > test-matrix.yaml <<EOF
metadata:
  generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  filter: $(echo "$TEST_FILTER" | sed 's/|/, /g')
  ignore: $(echo "$TEST_IGNORE" | sed 's/|/, /g')
  totalTests: ${#tests[@]}

tests:
EOF

for test in "${tests[@]}"; do
    IFS='|' read -r name dialer listener transport <<< "$test"

    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" impls.yaml)
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" impls.yaml)

    cat >> test-matrix.yaml <<EOF
  - name: $name
    dialer: $dialer
    listener: $listener
    transport: $transport
    dialerSnapshot: snapshots/$dialer_commit.zip
    listenerSnapshot: snapshots/$listener_commit.zip
EOF
done

# Cache the generated matrix
cp test-matrix.yaml "$cache_file"

echo "✓ Generated test matrix with ${#tests[@]} tests"
echo "  Cached as: ${cache_key:0:8}.yaml"
