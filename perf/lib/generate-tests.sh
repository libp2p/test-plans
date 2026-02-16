#!/usr/bin/env bash
# Generate test matrix from ${IMAGES_YAML} with filtering
# Outputs test-matrix.yaml with content-addressed caching
# Permutations: dialer × listener × transport × secureChannel × muxer

##### 1. SETUP

set -ueo pipefail

trap 'echo "ERROR in generate-tests.sh at line $LINENO: Command exited with status $?" >&2' ERR

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-filter-engine.sh"
source "${SCRIPT_LIB_DIR}/lib-generate-tests.sh"
source "${SCRIPT_LIB_DIR}/lib-host-os.sh"
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

# Perf entity IDs
readarray -t all_baseline_ids < <(get_entity_ids "baselines")

# All transport names
readarray -t all_transport_names < <(get_transport_names "implementations")

# All secure channel names
readarray -t all_secure_names < <(get_secure_names "implementations")

# All muxer names
readarray -t all_muxer_names < <(get_muxer_names "implementations")

# Save original filters for display
ORIGINAL_IMPL_SELECT="${IMPL_SELECT}"
ORIGINAL_IMPL_IGNORE="${IMPL_IGNORE}"
ORIGINAL_BASELINE_SELECT="${BASELINE_SELECT}"
ORIGINAL_BASELINE_IGNORE="${BASELINE_IGNORE}"
ORIGINAL_TRANSPORT_SELECT="${TRANSPORT_SELECT}"
ORIGINAL_TRANSPORT_IGNORE="${TRANSPORT_IGNORE}"
ORIGINAL_SECURE_SELECT="${SECURE_SELECT}"
ORIGINAL_SECURE_IGNORE="${SECURE_IGNORE}"
ORIGINAL_MUXER_SELECT="${MUXER_SELECT}"
ORIGINAL_MUXER_IGNORE="${MUXER_IGNORE}"
ORIGINAL_TEST_SELECT="${TEST_SELECT}"
ORIGINAL_TEST_IGNORE="${TEST_IGNORE}"

# Expand implementation filters
if [ -n "${IMPL_SELECT}" ]; then
  EXPANDED_IMPL_SELECT=$(expand_filter_string "${IMPL_SELECT}" all_image_ids)
else
  EXPANDED_IMPL_SELECT=""
fi

if [ -n "${IMPL_IGNORE}" ]; then
  EXPANDED_IMPL_IGNORE=$(expand_filter_string "${IMPL_IGNORE}" all_image_ids)
else
  EXPANDED_IMPL_IGNORE=""
fi

# Expand baseline filters
if [ -n "${BASELINE_SELECT}" ]; then
  EXPANDED_BASELINE_SELECT=$(expand_filter_string "${BASELINE_SELECT}" all_baseline_ids)
else
  EXPANDED_BASELINE_SELECT=""
fi

if [ -n "${BASELINE_IGNORE}" ]; then
  EXPANDED_BASELINE_IGNORE=$(expand_filter_string "${BASELINE_IGNORE}" all_baseline_ids)
else
  EXPANDED_BASELINE_IGNORE=""
fi

# Expand transport filters
if [ -n "${TRANSPORT_SELECT}" ]; then
  EXPANDED_TRANSPORT_SELECT=$(expand_filter_string "${TRANSPORT_SELECT}" all_transport_names)
else
  EXPANDED_TRANSPORT_SELECT=""
fi

if [ -n "${TRANSPORT_IGNORE}" ]; then
  EXPANDED_TRANSPORT_IGNORE=$(expand_filter_string "${TRANSPORT_IGNORE}" all_transport_names)
else
  EXPANDED_TRANSPORT_IGNORE=""
fi

# Expand secure channel filters
if [ -n "${SECURE_SELECT}" ]; then
  EXPANDED_SECURE_SELECT=$(expand_filter_string "${SECURE_SELECT}" all_secure_names)
else
  EXPANDED_SECURE_SELECT=""
fi

if [ -n "${SECURE_IGNORE}" ]; then
  EXPANDED_SECURE_IGNORE=$(expand_filter_string "${SECURE_IGNORE}" all_secure_names)
else
  EXPANDED_SECURE_IGNORE=""
fi

# Expand muxer filters
if [ -n "${MUXER_SELECT}" ]; then
  EXPANDED_MUXER_SELECT=$(expand_filter_string "${MUXER_SELECT}" all_muxer_names)
else
  EXPANDED_MUXER_SELECT=""
fi

if [ -n "${MUXER_IGNORE}" ]; then
  EXPANDED_MUXER_IGNORE=$(expand_filter_string "${MUXER_IGNORE}" all_muxer_names)
else
  EXPANDED_MUXER_IGNORE=""
fi

# Expand test SELECT filter
if [ -n "${TEST_SELECT}" ]; then
  EXPANDED_TEST_SELECT=$(expand_filter_string "${TEST_SELECT}" all_image_ids)
else
  EXPANDED_TEST_SELECT=""
fi

# Expand test IGNORE filter
if [ -n "${TEST_IGNORE}" ]; then
  EXPANDED_TEST_IGNORE=$(expand_filter_string "${TEST_IGNORE}" all_image_ids)
else
  EXPANDED_TEST_IGNORE=""
fi

##### 3. DISPLAY FILTER EXPANSION

# Implementation filters
print_filter_expansion \
  "ORIGINAL_IMPL_SELECT" \
  "EXPANDED_IMPL_SELECT" \
  "Implementation select" \
  "No impl-select specified (will select all implementations)"

print_filter_expansion \
  "ORIGINAL_IMPL_IGNORE" \
  "EXPANDED_IMPL_IGNORE" \
  "Implementation ignore" \
  "No impl-ignore specified (will ignore none)"

# Baseline filters
print_filter_expansion \
  "ORIGINAL_BASELINE_SELECT" \
  "EXPANDED_BASELINE_SELECT" \
  "Baseline select" \
  "No baseline-select specified (will select all baselines)"

print_filter_expansion \
  "ORIGINAL_BASELINE_IGNORE" \
  "EXPANDED_BASELINE_IGNORE" \
  "Baseline ignore" \
  "No baseline-ignore specified (will ignore none)"

# Transport filters
print_filter_expansion \
  "ORIGINAL_TRANSPORT_SELECT" \
  "EXPANDED_TRANSPORT_SELECT" \
  "Transport select" \
  "No transport-select specified (will select all transports)"

print_filter_expansion \
  "ORIGINAL_TRANSPORT_IGNORE" \
  "EXPANDED_TRANSPORT_IGNORE" \
  "Transport ignore" \
  "No transport-ignore specified (will ignore none)"

# Secure channel filters
print_filter_expansion \
  "ORIGINAL_SECURE_SELECT" \
  "EXPANDED_SECURE_SELECT" \
  "Secure channel select" \
  "No secure-select specified (will select all secure channels)"

print_filter_expansion \
  "ORIGINAL_SECURE_IGNORE" \
  "EXPANDED_SECURE_IGNORE" \
  "Secure channel ignore" \
  "No secure-ignore specified (will ignore none)"

# Muxer filters
print_filter_expansion \
  "ORIGINAL_MUXER_SELECT" \
  "EXPANDED_MUXER_SELECT" \
  "Muxer select" \
  "No muxer-select specified (will select all muxers)"

print_filter_expansion \
  "ORIGINAL_MUXER_IGNORE" \
  "EXPANDED_MUXER_IGNORE" \
  "Muxer ignore" \
  "No muxer-ignore specified (will ignore none)"

# Test name filters
print_filter_expansion \
  "ORIGINAL_TEST_SELECT" \
  "EXPANDED_TEST_SELECT" \
  "Test select" \
  "No test-select specified (will select all tests)"

print_filter_expansion \
  "ORIGINAL_TEST_IGNORE" \
  "EXPANDED_TEST_IGNORE" \
  "Test ignore" \
  "No test-ignore specified (will ignore none)"

echo ""

##### 4. CACHE CHECK AND EARLY EXIT

# Check cache (with optional force rebuild)
# Use TEST_RUN_KEY from parent (run.sh) if available
print_message "Checking for cached test-matrix.yaml file"
indent
if check_and_load_cache "${TEST_RUN_KEY}" "${CACHE_DIR}/test-run-matrix" "${TEST_PASS_DIR}/test-matrix.yaml" "${FORCE_MATRIX_REBUILD}" "${TEST_TYPE}"; then
  unindent
  unindent
  exit 0
fi
unindent

echo ""

##### 5. FILTERING

print_message "Filtering implementations..."
# Stage 1: SELECT
readarray -t selected_image_ids < <(select_from_list all_image_ids "${EXPANDED_IMPL_SELECT}")
# Stage 2: IGNORE
readarray -t filtered_image_ids < <(ignore_from_list selected_image_ids "${EXPANDED_IMPL_IGNORE}")
indent
print_success "Filtered to ${#filtered_image_ids[@]} implementations (${#all_image_ids[@]} total)"
unindent

print_message "Filtering baselines..."
# Stage 1: SELECT
readarray -t selected_baseline_ids < <(select_from_list all_baseline_ids "${EXPANDED_BASELINE_SELECT}")
# Stage 2: IGNORE
readarray -t filtered_baseline_ids < <(ignore_from_list selected_baseline_ids "${EXPANDED_BASELINE_IGNORE}")
indent
print_success "Filtered to ${#filtered_baseline_ids[@]} baselines (${#all_baseline_ids[@]} total)"
unindent

print_message "Filtering transports..."
# Stage 1: SELECT
readarray -t selected_transport_names < <(select_from_list all_transport_names "${EXPANDED_TRANSPORT_SELECT}")
# Stage 2: IGNORE
readarray -t filtered_transport_names < <(ignore_from_list selected_transport_names "${EXPANDED_TRANSPORT_IGNORE}")
indent
print_success "Filtered to ${#filtered_transport_names[@]} transports (${#all_transport_names[@]} total)"
unindent

print_message "Filtering secure channels..."
# Stage 1: SELECT
readarray -t selected_secure_names < <(select_from_list all_secure_names "${EXPANDED_SECURE_SELECT}")
# Stage 2: IGNORE
readarray -t filtered_secure_names < <(ignore_from_list selected_secure_names "${EXPANDED_SECURE_IGNORE}")
indent
print_success "Filtered to ${#filtered_secure_names[@]} secure channels (${#all_secure_names[@]} total)"
unindent

print_message "Filtering muxers..."
# Stage 1: SELECT
readarray -t selected_muxer_names < <(select_from_list all_muxer_names "${EXPANDED_MUXER_SELECT}")
# Stage 2: IGNORE
readarray -t filtered_muxer_names < <(ignore_from_list selected_muxer_names "${EXPANDED_MUXER_IGNORE}")
indent
print_success "Filtered to ${#filtered_muxer_names[@]} muxers (${#all_muxer_names[@]} total)"
unindent

echo ""

##### 6. LOAD PARAMETER LISTS

# Load baseline data for ALL baselines (needed for ignored test generation)
print_message "Loading baseline data into memory..."

declare -A baseline_transports

for baseline_id in "${all_baseline_ids[@]}"; do
  transports=$(yq eval ".baselines[] | select(.id == \"${baseline_id}\") | .transports | join(\" \")" "${IMAGES_YAML}")
  baseline_transports["${baseline_id}"]="${transports}"
done

indent
print_success "Loaded data for ${#all_baseline_ids[@]} baselines"
unindent

# Load main implementation data for ALL implementations (needed for ignored test generation)
print_message "Loading implementation data into memory..."

declare -A image_transports
declare -A image_secure
declare -A image_muxers
declare -A image_dial_only
declare -A image_commit
declare -A image_legacy

for image_id in "${all_image_ids[@]}"; do
  transports=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .transports | join(\" \")" "${IMAGES_YAML}")
  secure=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .secureChannels | join(\" \")" "${IMAGES_YAML}")
  muxers=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .muxers | join(\" \")" "${IMAGES_YAML}")
  dial_only=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .dialOnly | join(\" \")" "${IMAGES_YAML}" 2>/dev/null || echo "")
  commit=$(yq eval ".implementations[] | select (.id == \"${image_id}\") | .source.commit" "${IMAGES_YAML}" 2>/dev/null || echo "")
  legacy=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .legacy // false" "${IMAGES_YAML}" 2>/dev/null || echo "false")

  image_transports["${image_id}"]="${transports}"
  image_secure["${image_id}"]="${secure}"
  image_muxers["${image_id}"]="${muxers}"
  image_dial_only["${image_id}"]="${dial_only}"
  if [ -n "${commit}" ]; then
    image_commit["${image_id}"]="${commit}"
  fi
  image_legacy["${image_id}"]="${legacy}"
done

indent
print_success "Loaded data for ${#all_image_ids[@]} implementations"
unindent

echo ""

##### 7. GENERATE TEST MATRIX

# Initialize baseline test lists
baseline_tests=()
ignored_baseline_tests=()

print_message "Generating baseline test combinations..."

# Iterate through ALL baselines and track selected vs ignored
for dialer_id in "${all_baseline_ids[@]}"; do
  dialer_transports="${baseline_transports[${dialer_id}]}"

  for listener_id in "${all_baseline_ids[@]}"; do
    # Check if BOTH dialer AND listener are in filtered baseline list
    test_is_selected=false
    if [[ " ${filtered_baseline_ids[*]} " =~ " ${dialer_id} " ]] && [[ " ${filtered_baseline_ids[*]} " =~ " ${listener_id} " ]]; then
      test_is_selected=true
    fi

    listener_transports="${baseline_transports[${listener_id}]}"

    # Find common transports
    common_transports=$(get_common "${dialer_transports}" "${listener_transports}")

    # Skip if no common transports
    [ -z "${common_transports}" ] && continue

    for transport in ${common_transports}; do
      # Baseline test name
      test_id="${dialer_id} x ${listener_id} (${transport})"

      # Apply test name filtering (Stage 3: TEST filters)
      test_name_selected=true

      # Stage 3.1: Apply TEST_SELECT filter
      if [ -n "${EXPANDED_TEST_SELECT}" ]; then
        test_name_selected=false
        if filter_matches "${test_id}" "${EXPANDED_TEST_SELECT}"; then
          test_name_selected=true
        fi
      fi

      # Stage 3.2: Apply TEST_IGNORE filter
      if [ "${test_name_selected}" == "true" ] && [ -n "${EXPANDED_TEST_IGNORE}" ]; then
        if filter_matches "${test_id}" "${EXPANDED_TEST_IGNORE}"; then
          test_name_selected=false
        fi
      fi

      # Add to selected or ignored list based on entity membership AND test name filtering
      if [ "${test_is_selected}" == "true" ] && [ "${test_name_selected}" == "true" ]; then
        # Select baseline test
        baseline_tests+=("${test_id}|${dialer_id}|${listener_id}|${transport}|null|null")
      else
        # Ignore baseline test
        ignored_baseline_tests+=("${test_id}|${dialer_id}|${listener_id}|${transport}|null|null")
      fi
    done
  done
done

indent
print_success "${#baseline_tests[@]} Selected"
print_error "${#ignored_baseline_tests[@]} Ignored"
unindent
echo ""

# Initialize test lists
main_tests=()
ignored_main_tests=()

print_message "Generating main test combinations..."

# Iterate through ALL implementations and track selected vs ignored
for dialer_id in "${all_image_ids[@]}"; do
  dialer_transports="${image_transports[${dialer_id}]}"
  dialer_secure="${image_secure[${dialer_id}]}"
  dialer_muxers="${image_muxers[${dialer_id}]}"

  dialer_selected=true

  if [[ ! " ${filtered_image_ids[*]} " =~ " ${dialer_id} " ]]; then
    print_debug "${dialer_id} is an ignored id"
    dialer_selected=false
  fi

  for listener_id in "${all_image_ids[@]}"; do
    listener_transports="${image_transports[${listener_id}]}"
    listener_secure="${image_secure[${listener_id}]}"
    listener_muxers="${image_muxers[${listener_id}]}"

    listener_selected=true

    if [[ ! " ${filtered_image_ids[*]} " =~ " ${listener_id} " ]]; then
      print_debug "${listener_id} is an ignored id"
      listener_selected=false
    fi

    # Find common transports
    common_transports=$(get_common "${dialer_transports}" "${listener_transports}")

    # Skip if no common transports
    [ -z "${common_transports}" ] && continue

    # Process each common transport
    for transport in ${common_transports}; do

      transport_selected=true

      if [[ ! " ${filtered_transport_names[*]} " =~ " ${transport} " ]]; then
        print_debug "${transport} is an ignored transport"
        transport_selected=false
      fi

      if is_standalone_transport "${transport}"; then

        # Integrated transport with built-in secure channel and muxer
        test_id="${dialer_id} x ${listener_id} (${transport})"

        # Apply test name filtering (Stage 3: TEST filters)
        test_name_selected=true

        # Stage 3.1: Apply TEST_SELECT filter
        if [ -n "${EXPANDED_TEST_SELECT}" ]; then
          test_name_selected=false
          if filter_matches "${test_id}" "${EXPANDED_TEST_SELECT}"; then
            test_name_selected=true
          fi
        fi

        # Stage 3.2: Apply TEST_IGNORE filter
        if [ "${test_name_selected}" == "true" ] && [ -n "${EXPANDED_TEST_IGNORE}" ]; then
          if filter_matches "${test_id}" "${EXPANDED_TEST_IGNORE}"; then
            test_name_selected=false
          fi
        fi

        # Add to selected or ignored list based on entity membership AND test name filtering
        if [ "${dialer_selected}" == "true" ] && \
           [ "${listener_selected}" == "true" ] && \
           [ "${transport_selected}" == "true" ] && \
           [ "${test_name_selected}" == "true" ]; then
          # Select main test
          print_debug "${test_id} is selected"
          main_tests+=("${test_id}|${dialer_id}|${listener_id}|${transport}|null|null")
        else
          # Ignore main test
          print_debug "${test_id} is ignored"
          ignored_main_tests+=("${test_id}|${dialer_id}|${listener_id}|${transport}|null|null")
        fi

      else

        # Find common secure channels and muxers
        common_secure=$(get_common "${dialer_secure}" "${listener_secure}")
        common_muxers=$(get_common "${dialer_muxers}" "${listener_muxers}")

        # Skip if no common secureChannel or muxer
        [ -z "${common_secure}" ] && continue
        [ -z "${common_muxers}" ] && continue

        # Generate all combinations
        for secure in ${common_secure}; do

          secure_selected=true

          if [[ ! " ${filtered_secure_names[*]} " =~ " ${secure} " ]]; then
            print_debug "${secure} is an ignored secure channel"
            secure_selected=false
          fi

          for muxer in ${common_muxers}; do

            muxer_selected=true

            if [[ ! " ${filtered_muxer_names[*]} " =~ " ${muxer} " ]]; then
              print_debug "${muxer} is an ignored muxer"
              muxer_selected=false
            fi

            # Layered transport with secure channel and muxer
            test_id="${dialer_id} x ${listener_id} (${transport}, ${secure}, ${muxer})"

            # Apply test name filtering (Stage 3: TEST filters)
            test_name_selected=true

            # Stage 3.1: Apply TEST_SELECT filter
            if [ -n "${EXPANDED_TEST_SELECT}" ]; then
              test_name_selected=false
              if filter_matches "${test_id}" "${EXPANDED_TEST_SELECT}"; then
                test_name_selected=true
              fi
            fi

            # Stage 3.2: Apply TEST_IGNORE filter
            if [ "${test_name_selected}" == "true" ] && [ -n "${EXPANDED_TEST_IGNORE}" ]; then
              if filter_matches "${test_id}" "${EXPANDED_TEST_IGNORE}"; then
                test_name_selected=false
              fi
            fi

            # Add to selected or ignored list based on entity membership AND test name filtering
            if [ "${dialer_selected}" == "true" ] && \
               [ "${listener_selected}" == "true" ] && \
               [ "${transport_selected}" == "true" ] && \
               [ "${secure_selected}" == "true" ] && \
               [ "${muxer_selected}" == "true" ] && \
               [ "${test_name_selected}" == "true" ]; then
              # Select main test
              print_debug "${test_id} is selected"
              main_tests+=("${test_id}|${dialer_id}|${listener_id}|${transport}|${secure}|${muxer}")
            else
              # Ignore main test
              print_debug "${test_id} is ignored"
              ignored_main_tests+=("${test_id}|${dialer_id}|${listener_id}|${transport}|${secure}|${muxer}")
            fi
          done
        done
      fi
    done
  done
done

indent
print_success "${#main_tests[@]} Selected"
print_error "${#ignored_main_tests[@]} Ignored"
unindent
echo ""

##### 8. OUTPUT TEST MATRIX

output_tests() {
  local name=$1
  local entity_type=$2
  local -n tests=$3

  # Add list of tests
  cat >> "${TEST_PASS_DIR}/test-matrix.yaml" <<EOF

${name}:
EOF

  for test in "${tests[@]}"; do
    IFS='|' read -r id dialer listener transport secure_channel muxer <<< "${test}"

    # Get commits, if they exist
    local dialer_commit=$(get_source_commit "${entity_type}" "${dialer}")
    local dialer_image_name=$(get_image_name "${TEST_TYPE}" "${entity_type}" "${dialer}")
    local listener_commit=$(get_source_commit "${entity_type}" "${listener}")
    local listener_image_name=$(get_image_name "${TEST_TYPE}" "${entity_type}" "${listener}")

    local dialer_legacy="${image_legacy[${dialer}]:-false}"
    local listener_legacy="${image_legacy[${listener}]:-false}"

    cat >> "${TEST_PASS_DIR}/test-matrix.yaml" <<EOF
  - id: "${id}"
    transport: ${transport}
    secureChannel: ${secure_channel}
    muxer: ${muxer}
    dialer:
      id: ${dialer}
      imageName: ${dialer_image_name}
EOF

    if [ ! -z "${dialer_commit}" ]; then
      echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${TEST_PASS_DIR}/test-matrix.yaml"
    fi
    if [ "${dialer_legacy}" == "true" ]; then
      echo "      legacy: true" >> "${TEST_PASS_DIR}/test-matrix.yaml"
    fi

    cat >> "${TEST_PASS_DIR}/test-matrix.yaml" <<EOF
    listener:
      id: ${listener}
      imageName: ${listener_image_name}
EOF
    if [ ! -z "${listener_commit}" ]; then
      echo "      snapshot: snapshots/${listener_commit}.zip" >> "${TEST_PASS_DIR}/test-matrix.yaml"
    fi
    if [ "${listener_legacy}" == "true" ]; then
      echo "      legacy: true" >> "${TEST_PASS_DIR}/test-matrix.yaml"
    fi
  done
}

# Generate test-matrix.yaml
cat > "${TEST_PASS_DIR}/test-matrix.yaml" <<EOF
metadata:
  implSelect: |-
    ${ORIGINAL_IMPL_SELECT}
  implIgnore: |-
    ${ORIGINAL_IMPL_IGNORE}
  baselineSelect: |-
    ${ORIGINAL_BASELINE_SELECT}
  baselineIgnore: |-
    ${ORIGINAL_BASELINE_IGNORE}
  transportSelect: |-
    ${ORIGINAL_TRANSPORT_SELECT}
  transportIgnore: |-
    ${ORIGINAL_TRANSPORT_IGNORE}
  secureSelect: |-
    ${ORIGINAL_SECURE_SELECT}
  secureIgnore: |-
    ${ORIGINAL_SECURE_IGNORE}
  muxerSelect: |-
    ${ORIGINAL_MUXER_SELECT}
  muxerIgnore: |-
    ${ORIGINAL_MUXER_IGNORE}
  testSelect: |-
    ${ORIGINAL_TEST_SELECT}
  testIgnore: |-
    ${ORIGINAL_TEST_IGNORE}
  uploadBytes: ${UPLOAD_BYTES}
  downloadBytes: ${DOWNLOAD_BYTES}
  iterations: ${ITERATIONS}
  durationPerIteration: ${DURATION_PER_ITERATION}
  latencyIterations: ${LATENCY_ITERATIONS}
  totalBaselines: ${#baseline_tests[@]}
  ignoredBaselines: ${#ignored_baseline_tests[@]}
  totalTests: ${#main_tests[@]}
  ignoredTests: ${#ignored_main_tests[@]}
  debug: ${DEBUG}
EOF

# output selected baseline tests
output_tests "baselines" "baselines" baseline_tests

# output ignored baseline tests
output_tests "ignoredBaselines" "baselines" ignored_baseline_tests

# output selected tests
output_tests "tests" "implementations" main_tests

# output ignored tests
output_tests "ignoredTests" "implementations" ignored_main_tests

# Copy ${IMAGES_YAML} for reference and cache the test-matrix.yaml file
cp "${IMAGES_YAML}" "${TEST_PASS_DIR}/"
print_success "Copied ${IMAGES_YAML}: ${TEST_PASS_DIR}/${IMAGES_YAML}"
print_success "Generated test-matrix.yaml: ${TEST_PASS_DIR}/test-matrix.yaml"
indent
save_to_cache "${TEST_PASS_DIR}/test-matrix.yaml" "${TEST_RUN_KEY}" "${CACHE_DIR}/test-run-matrix" "${TEST_TYPE}"
unindent
exit 0
