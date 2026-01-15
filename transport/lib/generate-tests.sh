#!/bin/bash
# Generate test matrix from ${IMAGES_YAML} with filtering
# Outputs test-matrix.yaml with content-addressed caching
# Permutations: dialer × listener × transport × secureChannel × muxer

##### 1. SETUP

set -euo pipefail

trap 'echo "ERROR in generate-tests.sh at line $LINENO: Command exited with status $?" >&2' ERR

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-filter-engine.sh"
source "${SCRIPT_LIB_DIR}/lib-generate-tests.sh"
source "${SCRIPT_LIB_DIR}/lib-image-building.sh"
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
ORIGINAL_TEST_IGNORE="${TEST_IGNORE}"
ORIGINAL_TRANSPORT_IGNORE="${TRANSPORT_IGNORE}"
ORIGINAL_SECURE_IGNORE="${SECURE_IGNORE}"
ORIGINAL_MUXER_IGNORE="${MUXER_IGNORE}"

if [ -n "${TEST_IGNORE}" ]; then
  EXPANDED_TEST_IGNORE=$(expand_filter_string "${TEST_IGNORE}" all_image_ids)
else
  EXPANDED_TEST_IGNORE=""
fi

if [ -n "${TRANSPORT_IGNORE}" ]; then
  EXPANDED_TRANSPORT_IGNORE=$(expand_filter_string "${TRANSPORT_IGNORE}" all_transport_names)
else
  EXPANDED_TRANSPORT_IGNORE=""
fi

if [ -n "${SECURE_IGNORE}" ]; then
  EXPANDED_SECURE_IGNORE=$(expand_filter_string "${SECURE_IGNORE}" all_secure_names)
else
  EXPANDED_SECURE_IGNORE=""
fi

if [ -n "${MUXER_IGNORE}" ]; then
  EXPANDED_MUXER_IGNORE=$(expand_filter_string "${MUXER_IGNORE}" all_muxer_names)
else
  EXPANDED_MUXER_IGNORE=""
fi

##### 3. DISPLAY FILTER EXPANSION

# test ignore
print_filter_expansion \
  "ORIGINAL_TEST_IGNORE" \
  "EXPANDED_TEST_IGNORE" \
  "Test ignore" \
  "No test-ignore specified (will ignore none)"

# transport ignore
print_filter_expansion \
  "ORIGINAL_TRANSPORT_IGNORE" \
  "EXPANDED_TRANSPORT_IGNORE" \
  "Transport ignore" \
  "No transport-ignore specified (will ignore none)"

# secure ignore
print_filter_expansion \
  "ORIGINAL_SECURE_IGNORE" \
  "EXPANDED_SECURE_IGNORE" \
  "Secure channel ignore" \
  "No secure-ignore specified (will ignore none)"

# muxer ignore
print_filter_expansion \
  "ORIGINAL_MUXER_IGNORE" \
  "EXPANDED_MUXER_IGNORE" \
  "Muxer ignore" \
  "No muxer-ignore specified (will ignore none)"

echo ""

##### 4. CACHE CHECK AND EARLY EXIT

# Check cache (with optional force rebuild)
# Use TEST_RUN_KEY from parent (run.sh) if available
print_message "Checking for cached test-matrix.yaml file"
indent
if check_and_load_cache "${TEST_RUN_KEY}" "${CACHE_DIR}/test-run-matrix" "${TEST_PASS_DIR}/test-matrix.yaml" "${FORCE_MATRIX_REBUILD}" "${TEST_TYPE}"; then
  unindent
  exit 0
fi
unindent

echo ""

##### 5. FILTERING

print_message "Filtering implementations..."
readarray -t filtered_image_ids < <(filter all_image_ids "${EXPANDED_TEST_IGNORE}")
indent
print_success "Filtered to ${#filtered_image_ids[@]} implementations (${#all_image_ids[@]} total)"
unindent

print_message "Filtering transports..."
readarray -t filtered_transport_names < <(filter all_transport_names "${EXPANDED_TRANSPORT_IGNORE}")
indent
print_success "Filtered to ${#filtered_transport_names[@]} transports (${#all_transport_names[@]} total)"
unindent

print_message "Filtering secure channels..."
readarray -t filtered_secure_names < <(filter all_secure_names "${EXPANDED_SECURE_IGNORE}")
indent
print_success "Filtered to ${#filtered_secure_names[@]} secure channels (${#all_secure_names[@]} total)"
unindent

print_message "Filtering muxers..."
readarray -t filtered_muxer_names < <(filter all_muxer_names "${EXPANDED_MUXER_IGNORE}")
indent
print_success "Filtered to ${#filtered_muxer_names[@]} muxers (${#all_muxer_names[@]} total)"
unindent

echo ""

##### 6. LOAD PARAMETER LISTS

# Load main implementation data for ALL implementations (needed for ignored test generation)
print_message "Loading implementation data into memory..."

declare -A image_transports
declare -A image_secure
declare -A image_muxers
declare -A image_dial_only
declare -A image_commit

for image_id in "${all_image_ids[@]}"; do
  transports=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .transports | join(\" \")" "${IMAGES_YAML}")
  secure=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .secureChannels | join(\" \")" "${IMAGES_YAML}")
  muxers=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .muxers | join(\" \")" "${IMAGES_YAML}")
  dial_only=$(yq eval ".implementations[] | select(.id == \"${image_id}\") | .dialOnly | join(\" \")" "${IMAGES_YAML}" 2>/dev/null || echo "")
  commit=$(yq eval ".implementations[] | select (.id == \"${image_id}\") | .source.commit" "${IMAGES_YAML}" 2>/dev/null || echo "")

  image_transports["${image_id}"]="${transports}"
  image_secure["${image_id}"]="${secure}"
  image_muxers["${image_id}"]="${muxers}"
  image_dial_only["${image_id}"]="${dial_only}"
  if [ -n "${commit}" ]; then
    image_commit["${image_id}"]="${commit}"
  fi
done

indent
print_success "Loaded data for ${#all_image_ids[@]} implementations"
unindent

echo ""

##### 7. GENERATE TEST MATRIX

# Initialize test lists
main_tests=()
ignored_main_tests=()

# Determine worker count (from environment, defaults to nproc)
WORKER_COUNT="${WORKER_COUNT:-$(nproc 2>/dev/null || echo 4)}"

# Worker function to generate tests for a chunk of dialers
# Args: worker_id dialer_id1 dialer_id2 ...
generate_tests_worker() {
  local worker_id=$1
  shift
  local dialer_chunk=("$@")

  local worker_selected="${TEST_PASS_DIR}/worker-${worker_id}-selected.yaml"
  local worker_ignored="${TEST_PASS_DIR}/worker-${worker_id}-ignored.yaml"

  > "${worker_selected}"
  > "${worker_ignored}"

  # Load associative arrays from serialized files
  declare -A image_transports
  declare -A image_secure
  declare -A image_muxers
  declare -A image_dial_only
  declare -A image_commit

  while IFS='|' read -r key value; do
    image_transports["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/transports.dat"

  while IFS='|' read -r key value; do
    image_secure["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/secure.dat"

  while IFS='|' read -r key value; do
    image_muxers["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/muxers.dat"

  if [ -f "${WORKER_DATA_DIR}/dial_only.dat" ]; then
    while IFS='|' read -r key value; do
      image_dial_only["${key}"]="${value}"
    done < "${WORKER_DATA_DIR}/dial_only.dat"
  fi

  if [ -f "${WORKER_DATA_DIR}/commits.dat" ]; then
    while IFS='|' read -r key value; do
      image_commit["${key}"]="${value}"
    done < "${WORKER_DATA_DIR}/commits.dat"
  fi

  for dialer_id in "${dialer_chunk[@]}"; do
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

      # Get commits for snapshot references
      local dialer_commit="${image_commit[${dialer_id}]:-}"
      local listener_commit="${image_commit[${listener_id}]:-}"

      # Get the image names 
      local dialer_image_name=$(get_image_name "implementations" "${dialer_id}")
      local listener_image_name=$(get_image_name "implementations" "${listener_id}")

      # Process each common transport
      for transport in ${common_transports}; do

        transport_selected=true

        if [[ ! " ${filtered_transport_names[*]} " =~ " ${transport} " ]]; then
          print_debug "${transport} is an ignored transport"
          transport_selected=false
        fi

        # Check if listener can handle this transport (not in dialOnly list)
        dial_only_transports="${image_dial_only[${listener_id}]:-}"
        case " ${dial_only_transports} " in
          *" ${transport} "*)
            continue  # Skip: listener has this transport in dialOnly
            ;;
        esac

        if is_standalone_transport "${transport}"; then

          # Integrated transport with built-in secure channel and muxer
          test_id="${dialer_id} x ${listener_id} (${transport})"

          # Add to selected or ignored list
          if [ "${dialer_selected}" == "true" ] && \
             [ "${listener_selected}" == "true" ] && \
             [ "${transport_selected}" == "true" ]; then

            # Select main test
            print_debug "${test_id} is selected"

            # Write YAML block
            cat >> "${worker_selected}" <<EOF
  - id: "${test_id}"
    transport: ${transport}
    secureChannel: null
    muxer: null
    dialer:
      id: ${dialer_id}
      imageName: ${dialer_image_name}
EOF
            if [ -n "${dialer_commit}" ]; then
              echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_selected}"
            fi
            cat >> "${worker_selected}" <<EOF
    listener:
      id: ${listener_id}
      imageName: ${listener_image_name}
EOF
            if [ -n "${listener_commit}" ]; then
              echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_selected}"
            fi
          else

            # Ignore main test
            print_debug "${test_id} is ignored"

            # Write YAML block
            cat >> "${worker_ignored}" <<EOF
  - id: "${test_id}"
    transport: ${transport}
    secureChannel: null
    muxer: null
    dialer:
      id: ${dialer_id}
      imageName: ${dialer_image_name}
EOF
            if [ -n "${dialer_commit}" ]; then
              echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_ignored}"
            fi
            cat >> "${worker_ignored}" <<EOF
    listener:
      id: ${listener_id}
      imageName: ${listener_image_name}
EOF
            if [ -n "${listener_commit}" ]; then
              echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_ignored}"
            fi
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

              # Add to selected or ignored list
              if [ "${dialer_selected}" == "true" ] && \
                 [ "${listener_selected}" == "true" ] && \
                 [ "${transport_selected}" == "true" ] && \
                 [ "${secure_selected}" == "true" ] && \
                 [ "${muxer_selected}" == "true" ]; then

                # Select main test
                print_debug "${test_id} is selected"

                # Write YAML block
                cat >> "${worker_selected}" <<EOF
  - id: "${test_id}"
    transport: ${transport}
    secureChannel: ${secure}
    muxer: ${muxer}
    dialer:
      id: ${dialer_id}
      imageName: ${dialer_image_name}
EOF
                if [ -n "${dialer_commit}" ]; then
                  echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_selected}"
                fi
                cat >> "${worker_selected}" <<EOF
    listener:
      id: ${listener_id}
      imageName: ${listener_image_name}
EOF
                if [ -n "${listener_commit}" ]; then
                  echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_selected}"
                fi
              else

                # Ignore main test
                print_debug "${test_id} is ignored"

                # Write YAML block
                cat >> "${worker_ignored}" <<EOF
  - id: "${test_id}"
    transport: ${transport}
    secureChannel: ${secure}
    muxer: ${muxer}
    dialer:
      id: ${dialer_id}
      imageName: ${dialer_image_name}
EOF
                if [ -n "${dialer_commit}" ]; then
                  echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_ignored}"
                fi
                cat >> "${worker_ignored}" <<EOF
    listener:
      id: ${listener_id}
      imageName: ${listener_image_name}
EOF
                if [ -n "${listener_commit}" ]; then
                  echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_ignored}"
                fi
              fi
            done
          done
        fi
      done
    done
  done
}

# Serialize associative arrays to temp files for workers
# (Bash can't export associative array contents to subshells)
WORKER_DATA_DIR="${TEST_PASS_DIR}/worker-data"
mkdir -p "${WORKER_DATA_DIR}"

# Serialize image data
for key in "${!image_transports[@]}"; do
  echo "${key}|${image_transports[${key}]}" >> "${WORKER_DATA_DIR}/transports.dat"
done

for key in "${!image_secure[@]}"; do
  echo "${key}|${image_secure[${key}]}" >> "${WORKER_DATA_DIR}/secure.dat"
done

for key in "${!image_muxers[@]}"; do
  echo "${key}|${image_muxers[${key}]}" >> "${WORKER_DATA_DIR}/muxers.dat"
done

for key in "${!image_dial_only[@]}"; do
  echo "${key}|${image_dial_only[${key}]}" >> "${WORKER_DATA_DIR}/dial_only.dat"
done

for key in "${!image_commit[@]}"; do
  echo "${key}|${image_commit[${key}]}" >> "${WORKER_DATA_DIR}/commits.dat"
done

# Export necessary variables and functions for workers
export -f generate_tests_worker
export -f get_common
export -f get_image_name
export -f is_standalone_transport
export -f print_debug
export -f get_source_commit
export -f get_source_type
export TEST_PASS_DIR
export WORKER_DATA_DIR
export filtered_image_ids
export all_image_ids
export filtered_transport_names
export filtered_secure_names
export filtered_muxer_names

print_message "Generating main test combinations (using ${WORKER_COUNT} workers)..."

# Shard dialers across workers
total_dialers=${#all_image_ids[@]}
chunk_size=$(( (${total_dialers} + ${WORKER_COUNT} - 1) / ${WORKER_COUNT} ))

pids=()
for ((w=0; w<${WORKER_COUNT}; w++)); do
  start=$((${w} * ${chunk_size}))

  # Break if we've exceeded the array bounds
  if [ ${start} -ge ${total_dialers} ]; then
    break
  fi

  # Get chunk of dialers for this worker
  chunk=("${all_image_ids[@]:${start}:${chunk_size}}")

  # Skip if chunk is empty
  if [ ${#chunk[@]} -eq 0 ]; then
    continue
  fi

  # Launch worker in background
  generate_tests_worker "${w}" "${chunk[@]}" &
  pids+=($!)
done

# Wait for all workers to complete
for pid in "${pids[@]}"; do
  wait "${pid}"
done

# Count tests from worker YAML files
total_selected=0
total_ignored=0

for ((w=0; w<${WORKER_COUNT}; w++)); do
  if [ -f "${TEST_PASS_DIR}/worker-${w}-selected.yaml" ]; then
    count=$(grep -c "^  - id:" "${TEST_PASS_DIR}/worker-${w}-selected.yaml" 2>/dev/null || true)
    total_selected=$((${total_selected} + ${count}))
  fi

  if [ -f "${TEST_PASS_DIR}/worker-${w}-ignored.yaml" ]; then
    count=$(grep -c "^  - id:" "${TEST_PASS_DIR}/worker-${w}-ignored.yaml" 2>/dev/null || true)
    total_ignored=$((${total_ignored} + ${count}))
  fi
done

# Cleanup worker data directory
rm -rf "${WORKER_DATA_DIR}"

indent
print_success "${total_selected} Selected"
print_error "${total_ignored} Ignored"
unindent
echo ""

##### 8. OUTPUT TEST MATRIX

# Generate metadata section
cat > "${TEST_PASS_DIR}/test-matrix.yaml" <<EOF
metadata:
  ignore: |-
    ${TEST_IGNORE}
  transportIgnore: |-
    ${TRANSPORT_IGNORE}
  secureIgnore: |-
    ${SECURE_IGNORE}
  muxerIgnore: |-
    ${MUXER_IGNORE}
  totalTests: ${total_selected}
  ignoredTests: ${total_ignored}
  debug: ${DEBUG}

tests:
EOF

# Concatenate selected test YAML files from workers
for ((w=0; w<${WORKER_COUNT}; w++)); do
  if [ -f "${TEST_PASS_DIR}/worker-${w}-selected.yaml" ]; then
    cat "${TEST_PASS_DIR}/worker-${w}-selected.yaml" >> "${TEST_PASS_DIR}/test-matrix.yaml"
    rm -f "${TEST_PASS_DIR}/worker-${w}-selected.yaml"
  fi
done

# Add ignoredTests section
cat >> "${TEST_PASS_DIR}/test-matrix.yaml" <<EOF

ignoredTests:
EOF

# Concatenate ignored test YAML files from workers
for ((w=0; w<${WORKER_COUNT}; w++)); do
  if [ -f "${TEST_PASS_DIR}/worker-${w}-ignored.yaml" ]; then
    cat "${TEST_PASS_DIR}/worker-${w}-ignored.yaml" >> "${TEST_PASS_DIR}/test-matrix.yaml"
    rm -f "${TEST_PASS_DIR}/worker-${w}-ignored.yaml"
  fi
done

# Copy ${IMAGES_YAML} for reference and cache the test-matrix.yaml file
cp "${IMAGES_YAML}" "${TEST_PASS_DIR}/"
print_success "Copied ${IMAGES_YAML}: ${TEST_PASS_DIR}/${IMAGES_YAML}"
print_success "Generated test-matrix.yaml: ${TEST_PASS_DIR}/test-matrix.yaml"
indent
save_to_cache "${TEST_PASS_DIR}/test-matrix.yaml" "${TEST_RUN_KEY}" "${CACHE_DIR}/test-run-matrix" "${TEST_TYPE}"
unindent
exit 0
