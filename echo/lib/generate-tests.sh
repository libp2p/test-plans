#!/bin/bash
# Generate test matrix for Echo protocol interoperability tests
# Outputs test-matrix.yaml with content-addressed caching
# Permutations: js-server × py-client × transport × secureChannel × muxer

##### 1. SETUP

set -euo pipefail

trap 'echo "ERROR in generate-tests.sh at line $LINENO: Command exited with status $?" >&2' ERR

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-filter-engine.sh"
source "${SCRIPT_LIB_DIR}/lib-generate-tests.sh"
source "${SCRIPT_LIB_DIR}/lib-image-building.sh"
source "${SCRIPT_LIB_DIR}/lib-image-naming.sh"
source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"
source "${SCRIPT_LIB_DIR}/lib-test-filtering.sh"
source "${SCRIPT_LIB_DIR}/lib-test-images.sh"

##### 2. FILTER EXPANSION

# Load test aliases
load_aliases

# Get common entity IDs for negation expansion and ignored test generation
readarray -t all_image_ids < <(get_entity_ids "implementations")

# All transport names
readarray -t all_transport_names < <(get_transport_names "implementations")

# All secure channel names
readarray -t all_secure_names < <(get_secure_names "implementations")

# All muxer names
readarray -t all_muxer_names < <(get_muxer_names "implementations")

# Save original filters for display
ORIGINAL_IMPL_SELECT="${IMPL_SELECT}"
ORIGINAL_IMPL_IGNORE="${IMPL_IGNORE}"
ORIGINAL_TRANSPORT_SELECT="${TRANSPORT_SELECT}"
ORIGINAL_TRANSPORT_IGNORE="${TRANSPORT_IGNORE}"
ORIGINAL_SECURE_SELECT="${SECURE_SELECT}"
ORIGINAL_SECURE_IGNORE="${SECURE_IGNORE}"
ORIGINAL_MUXER_SELECT="${MUXER_SELECT}"
ORIGINAL_MUXER_IGNORE="${MUXER_IGNORE}"
ORIGINAL_TEST_SELECT="${TEST_SELECT}"
ORIGINAL_TEST_IGNORE="${TEST_IGNORE}"

# Expand filter strings
IMPL_SELECT=$(expand_filter_string "${IMPL_SELECT}" all_image_ids)
IMPL_IGNORE=$(expand_filter_string "${IMPL_IGNORE}" all_image_ids)
TRANSPORT_SELECT=$(expand_filter_string "${TRANSPORT_SELECT}" all_transport_names)
TRANSPORT_IGNORE=$(expand_filter_string "${TRANSPORT_IGNORE}" all_transport_names)
SECURE_SELECT=$(expand_filter_string "${SECURE_SELECT}" all_secure_names)
SECURE_IGNORE=$(expand_filter_string "${SECURE_IGNORE}" all_secure_names)
MUXER_SELECT=$(expand_filter_string "${MUXER_SELECT}" all_muxer_names)
MUXER_IGNORE=$(expand_filter_string "${MUXER_IGNORE}" all_muxer_names)

##### 3. CACHE MANAGEMENT

# Compute cache key for test matrix
CACHE_KEY=$(compute_test_cache_key)
TEST_MATRIX_FILE="${CACHE_DIR}/test-matrix/echo-${CACHE_KEY}.yaml"

# Check if cached test matrix exists
if [ -f "${TEST_MATRIX_FILE}" ]; then
    print_message "Using cached test matrix: ${TEST_MATRIX_FILE}"
    exit 0
fi

##### 4. GENERATE TEST MATRIX

print_message "Generating Echo protocol test matrix..."

# Create cache directory
mkdir -p "$(dirname "${TEST_MATRIX_FILE}")"

# Generate test combinations
{
    echo "# Echo Protocol Interoperability Test Matrix"
    echo "# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "# Cache Key: ${CACHE_KEY}"
    echo ""
    echo "tests:"
    
    # Get filtered implementations
    local js_servers=()
    local py_clients=()
    
    while IFS= read -r impl_id; do
        if [[ "${impl_id}" == *"js-libp2p"* ]]; then
            js_servers+=("${impl_id}")
        elif [[ "${impl_id}" == *"py-libp2p"* ]]; then
            py_clients+=("${impl_id}")
        fi
    done < <(filter_names "${IMPL_SELECT}" "${IMPL_IGNORE}" all_image_ids)
    
    # Generate test combinations
    local test_count=0
    for server in "${js_servers[@]}"; do
        for client in "${py_clients[@]}"; do
            # Get supported protocols for this combination
            local server_transports=($(get_implementation_transports "${server}"))
            local client_transports=($(get_implementation_transports "${client}"))
            local common_transports=($(get_common_elements server_transports client_transports))
            
            local server_secures=($(get_implementation_secures "${server}"))
            local client_secures=($(get_implementation_secures "${client}"))
            local common_secures=($(get_common_elements server_secures client_secures))
            
            local server_muxers=($(get_implementation_muxers "${server}"))
            local client_muxers=($(get_implementation_muxers "${client}"))
            local common_muxers=($(get_common_elements server_muxers client_muxers))
            
            # Filter protocols
            local filtered_transports=($(filter_names "${TRANSPORT_SELECT}" "${TRANSPORT_IGNORE}" common_transports))
            local filtered_secures=($(filter_names "${SECURE_SELECT}" "${SECURE_IGNORE}" common_secures))
            local filtered_muxers=($(filter_names "${MUXER_SELECT}" "${MUXER_IGNORE}" common_muxers))
            
            # Generate test for each combination
            for transport in "${filtered_transports[@]}"; do
                for secure in "${filtered_secures[@]}"; do
                    for muxer in "${filtered_muxers[@]}"; do
                        local test_name="echo-${server}-${client}-${transport}-${secure}-${muxer}"
                        
                        # Apply test-level filtering
                        if should_include_test "${test_name}" "${TEST_SELECT}" "${TEST_IGNORE}"; then
                            cat << EOF
  - name: "${test_name}"
    server: "${server}"
    client: "${client}"
    transport: "${transport}"
    secureChannel: "${secure}"
    muxer: "${muxer}"
    protocol: "/echo/1.0.0"
    timeout: 300
EOF
                            ((test_count++))
                        fi
                    done
                done
            done
        done
    done
    
    echo ""
    echo "# Total tests: ${test_count}"
    
} > "${TEST_MATRIX_FILE}"

print_message "Generated ${test_count} Echo protocol tests"
print_message "Test matrix saved: ${TEST_MATRIX_FILE}"

##### 5. HELPER FUNCTIONS

get_implementation_transports() {
    local impl_id="$1"
    yq eval ".implementations[] | select(.id == \"${impl_id}\") | .transports[]" "${IMAGES_YAML}"
}

get_implementation_secures() {
    local impl_id="$1"
    yq eval ".implementations[] | select(.id == \"${impl_id}\") | .secureChannels[]" "${IMAGES_YAML}"
}

get_implementation_muxers() {
    local impl_id="$1"
    yq eval ".implementations[] | select(.id == \"${impl_id}\") | .muxers[]" "${IMAGES_YAML}"
}

get_common_elements() {
    local -n arr1=$1
    local -n arr2=$2
    local common=()
    
    for elem1 in "${arr1[@]}"; do
        for elem2 in "${arr2[@]}"; do
            if [[ "${elem1}" == "${elem2}" ]]; then
                common+=("${elem1}")
                break
            fi
        done
    done
    
    printf '%s\n' "${common[@]}"
}

should_include_test() {
    local test_name="$1"
    local select_filter="$2"
    local ignore_filter="$3"
    
    # Apply test selection filter
    if [[ -n "${select_filter}" ]]; then
        if ! [[ "${test_name}" =~ ${select_filter} ]]; then
            return 1
        fi
    fi
    
    # Apply test ignore filter
    if [[ -n "${ignore_filter}" ]]; then
        if [[ "${test_name}" =~ ${ignore_filter} ]]; then
            return 1
        fi
    fi
    
    return 0
}