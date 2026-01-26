#!/usr/bin/env bash

# Generate test matrix for JS-libp2p Echo interoperability tests
# This script creates all test combinations between js-libp2p (server) and py-libp2p (client)

set -euo pipefail

# This script is sourced by run.sh, so variables are already available

# Load filter engine for alias expansion
source "${SCRIPT_DIR}/../lib/lib-filter-engine.sh"

# Generate test run key for caching
generate_test_run_key() {
    local images_hash
    images_hash=$(sha256sum "${SCRIPT_DIR}/images.yaml" | cut -d' ' -f1 | head -c 8)
    
    local filter_string="${TEST_SELECT:-}|${TEST_IGNORE:-}|${IMPL_SELECT:-}|${IMPL_IGNORE:-}|${TRANSPORT_SELECT:-}|${TRANSPORT_IGNORE:-}|${SECURE_SELECT:-}|${SECURE_IGNORE:-}|${MUXER_SELECT:-}|${MUXER_IGNORE:-}|${DEBUG:-false}"
    local filter_hash
    filter_hash=$(echo -n "$filter_string" | sha256sum | cut -d' ' -f1 | head -c 8)
    
    echo "${images_hash}-${filter_hash}"
}

# Check if test matrix is cached
TEST_RUN_KEY=$(generate_test_run_key)
TEST_MATRIX_FILE="${CACHE_DIR}/test-run-matrix/${TEST_TYPE}-${TEST_RUN_KEY}.yaml"

if [[ -f "$TEST_MATRIX_FILE" && "$FORCE_MATRIX_REBUILD" != "true" ]]; then
    echo "Using cached test matrix: $TEST_MATRIX_FILE"
    return 0
fi

echo "Generating test matrix..."
mkdir -p "$(dirname "$TEST_MATRIX_FILE")"

# Load implementations from images.yaml
IMPLEMENTATIONS=$(yq eval '.implementations[].id' "${SCRIPT_DIR}/images.yaml")

# Expand filter aliases
expand_aliases "${SCRIPT_DIR}/images.yaml"

# Get server and client implementations
SERVER_IMPLS=$(echo "$IMPLEMENTATIONS" | grep -E "js-libp2p-echo-server" || true)
CLIENT_IMPLS=$(echo "$IMPLEMENTATIONS" | grep -E "py-libp2p" || true)

# Apply implementation filters
if [[ -n "$IMPL_SELECT" ]]; then
    SERVER_IMPLS=$(echo "$SERVER_IMPLS" | grep -E "$EXPANDED_IMPL_SELECT" || true)
    CLIENT_IMPLS=$(echo "$CLIENT_IMPLS" | grep -E "$EXPANDED_IMPL_SELECT" || true)
fi

if [[ -n "$IMPL_IGNORE" ]]; then
    SERVER_IMPLS=$(echo "$SERVER_IMPLS" | grep -vE "$EXPANDED_IMPL_IGNORE" || true)
    CLIENT_IMPLS=$(echo "$CLIENT_IMPLS" | grep -vE "$EXPANDED_IMPL_IGNORE" || true)
fi

# Get supported protocols for each implementation
get_supported_protocols() {
    local impl="$1"
    local protocol_type="$2"  # transports, secureChannels, or muxers
    
    yq eval ".implementations[] | select(.id == \"$impl\") | .$protocol_type[]" "${SCRIPT_DIR}/images.yaml" 2>/dev/null || echo ""
}

# Generate test combinations
SELECTED_TESTS=()
IGNORED_TESTS=()

for server in $SERVER_IMPLS; do
    for client in $CLIENT_IMPLS; do
        # Get supported protocols for both implementations
        server_transports=$(get_supported_protocols "$server" "transports")
        client_transports=$(get_supported_protocols "$client" "transports")
        
        server_secure=$(get_supported_protocols "$server" "secureChannels")
        client_secure=$(get_supported_protocols "$client" "secureChannels")
        
        server_muxers=$(get_supported_protocols "$server" "muxers")
        client_muxers=$(get_supported_protocols "$client" "muxers")
        
        # Find common protocols
        common_transports=$(comm -12 <(echo "$server_transports" | sort) <(echo "$client_transports" | sort))
        common_secure=$(comm -12 <(echo "$server_secure" | sort) <(echo "$client_secure" | sort))
        common_muxers=$(comm -12 <(echo "$server_muxers" | sort) <(echo "$client_muxers" | sort))
        
        # Generate test combinations for each common protocol stack
        for transport in $common_transports; do
            for secure in $common_secure; do
                for muxer in $common_muxers; do
                    test_name="${client} x ${server} (${transport}, ${secure}, ${muxer})"
                    
                    # Apply transport filters
                    if [[ -n "$TRANSPORT_SELECT" && ! "$transport" =~ $TRANSPORT_SELECT ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    if [[ -n "$TRANSPORT_IGNORE" && "$transport" =~ $TRANSPORT_IGNORE ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    # Apply security filters
                    if [[ -n "$SECURE_SELECT" && ! "$secure" =~ $SECURE_SELECT ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    if [[ -n "$SECURE_IGNORE" && "$secure" =~ $SECURE_IGNORE ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    # Apply muxer filters
                    if [[ -n "$MUXER_SELECT" && ! "$muxer" =~ $MUXER_SELECT ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    if [[ -n "$MUXER_IGNORE" && "$muxer" =~ $MUXER_IGNORE ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    # Apply test name filters
                    if [[ -n "$TEST_SELECT" && ! "$test_name" =~ $TEST_SELECT ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    if [[ -n "$TEST_IGNORE" && "$test_name" =~ $TEST_IGNORE ]]; then
                        IGNORED_TESTS+=("$test_name")
                        continue
                    fi
                    
                    SELECTED_TESTS+=("$test_name")
                done
            done
        done
    done
done

# Write test matrix to file
{
    echo "# Test matrix for JS-libp2p Echo interoperability tests"
    echo "# Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "# Test run key: $TEST_RUN_KEY"
    echo ""
    echo "metadata:"
    echo "  testRunKey: \"$TEST_RUN_KEY\""
    echo "  generatedAt: \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\""
    echo "  testType: \"$TEST_TYPE\""
    echo "  filters:"
    echo "    testSelect: \"${TEST_SELECT:-}\""
    echo "    testIgnore: \"${TEST_IGNORE:-}\""
    echo "    implSelect: \"${IMPL_SELECT:-}\""
    echo "    implIgnore: \"${IMPL_IGNORE:-}\""
    echo "    transportSelect: \"${TRANSPORT_SELECT:-}\""
    echo "    transportIgnore: \"${TRANSPORT_IGNORE:-}\""
    echo "    secureSelect: \"${SECURE_SELECT:-}\""
    echo "    secureIgnore: \"${SECURE_IGNORE:-}\""
    echo "    muxerSelect: \"${MUXER_SELECT:-}\""
    echo "    muxerIgnore: \"${MUXER_IGNORE:-}\""
    echo "  debug: $DEBUG"
    echo ""
    echo "summary:"
    echo "  totalSelected: ${#SELECTED_TESTS[@]}"
    echo "  totalIgnored: ${#IGNORED_TESTS[@]}"
    echo ""
    echo "selected:"
    for test in "${SELECTED_TESTS[@]}"; do
        echo "  - \"$test\""
    done
    echo ""
    echo "ignored:"
    for test in "${IGNORED_TESTS[@]}"; do
        echo "  - \"$test\""
    done
} > "$TEST_MATRIX_FILE"

echo "Generated test matrix with ${#SELECTED_TESTS[@]} selected tests and ${#IGNORED_TESTS[@]} ignored tests"
echo "Test matrix saved to: $TEST_MATRIX_FILE"