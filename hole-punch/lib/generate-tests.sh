#!/bin/bash
# Generate test matrix from images.yaml with filtering
# Outputs test-matrix.yaml with content-addressed caching
# Permutations: dialer × listener × transport × secureChannel × muxer × relay × dialer_router × listener_router

##### 1. SETUP

set -euo pipefail

trap 'echo "ERROR in generate-tests.sh at line $LINENO: Command exited with status $?" >&2' ERR

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-filter-engine.sh"
source "${SCRIPT_LIB_DIR}/lib-generate-tests.sh"
source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"
source "${SCRIPT_LIB_DIR}/lib-test-filtering.sh"
source "${SCRIPT_LIB_DIR}/lib-test-images.sh"

##### 2. FILTER EXPANSION

# Load test aliases
load_aliases

# Get common entity IDs for negation expansion and ignored test generation
readarray -t all_image_ids < <(get_entity_ids "implementations")

# Hole-punch relays
readarray -t all_relay_ids < <(get_entity_ids "relays")

# Hole-punch routers
readarray -t all_router_ids < <(get_entity_ids "routers")

# All transport names for both relays and implementations
readarray -t all_transport_names < <(
  { get_transport_names "implementations"
    get_transport_names "relays"
  } | sort -u
)

# All secure channel names for both relays and implementations
readarray -t all_secure_names < <(
  { get_secure_names "implementations"
    get_secure_names "relays"
  } | sort -u
)

# All muxer names for both relays and implementations
readarray -t all_muxer_names < <(
  { get_muxer_names "implementations"
    get_muxer_names "relays"
  } | sort -u
)

# Save original filters for display
ORIGINAL_TEST_IGNORE="${TEST_IGNORE}"
ORIGINAL_RELAY_IGNORE="${RELAY_IGNORE}"
ORIGINAL_ROUTER_IGNORE="${ROUTER_IGNORE}"
ORIGINAL_TRANSPORT_IGNORE="${TRANSPORT_IGNORE}"
ORIGINAL_SECURE_IGNORE="${SECURE_IGNORE}"
ORIGINAL_MUXER_IGNORE="${MUXER_IGNORE}"

if [ -n "${TEST_IGNORE}" ]; then
  EXPANDED_TEST_IGNORE=$(expand_filter_string "${TEST_IGNORE}" all_image_ids)
else
  EXPANDED_TEST_IGNORE=""
fi

if [ -n "${RELAY_IGNORE}" ]; then
  EXPANDED_RELAY_IGNORE=$(expand_filter_string "${RELAY_IGNORE}" all_baseline_ids)
else
  EXPANDED_RELAY_IGNORE=""
fi

if [ -n "${ROUTER_IGNORE}" ]; then
  EXPANDED_ROUTER_IGNORE=$(expand_filter_string "${ROUTER_IGNORE}" all_baseline_ids)
else
  EXPANDED_ROUTER_IGNORE=""
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

# relay ignore
print_filter_expansion \
  "ORIGINAL_RELAY_IGNORE" \
  "EXPANDED_RELAY_IGNORE" \
  "Relay ignore" \
  "No relay-ignore specified (will ignore none)"

# relay ignore
print_filter_expansion \
  "ORIGINAL_ROUTER_IGNORE" \
  "EXPANDED_ROUTER_IGNORE" \
  "Router ignore" \
  "No router-ignore specified (will ignore none)"

# transort ignore
print_filter_expansion \
  "ORIGINAL_TRANSPORT_IGNORE" \
  "EXPANDED_TRANSPORT_IGNORE" \
  "Transport ignore" \
  "No transort-ignore specified (will ignore none)"

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

print_message "Filtering relay..."
readarray -t filtered_relay_ids < <(filter all_relay_ids "${EXPANDED_RELAY_IGNORE}")
indent
print_success "Filtered to ${#filtered_relay_ids[@]} baselines (${#all_relay_ids[@]} total)"
unindent

print_message "Filtering router..."
readarray -t filtered_router_ids < <(filter all_router_ids "${EXPANDED_ROUTER_IGNORE}")
indent
print_success "Filtered to ${#filtered_router_ids[@]} baselines (${#all_router_ids[@]} total)"
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

# Load implementation data for all relays
print_message "Loading relay data into memory..."

declare -A relay_transports
declare -A relay_secure
declare -A relay_muxers
declare -A relay_dial_only
declare -A relay_commit

for relay_id in "${all_relay_ids[@]}"; do
  transports=$(yq eval ".relays[] | select(.id == \"${relay_id}\") | .transports | join(\" \")" "${IMAGES_YAML}")
  secure=$(yq eval ".relays[] | select(.id == \"${relay_id}\") | .secureChannels | join(\" \")" "${IMAGES_YAML}")
  muxers=$(yq eval ".relays[] | select(.id == \"${relay_id}\") | .muxers | join(\" \")" "${IMAGES_YAML}")
  dial_only=$(yq eval ".relays[] | select(.id == \"${relay_id}\") | .dialOnly | join(\" \")" "${IMAGES_YAML}" 2>/dev/null || echo "")
  commit=$(yq eval ".relays[] | select (.id == \"${relay_id}\") | .source.commit" "${IMAGES_YAML}" 2>/dev/null || echo "")

  relay_transports["${relay_id}"]="${transports}"
  relay_secure["${relay_id}"]="${secure}"
  relay_muxers["${relay_id}"]="${muxers}"
  relay_dial_only["${relay_id}"]="${dial_only}"
  if [ -n "${commit}" ]; then
    relay_commit["${relay_id}"]="${commit}"
  fi
done

indent
print_success "Loaded data for ${#all_relay_ids[@]} relays"
unindent
echo ""

# Load implementation data for all routers
print_message "Loading router data into memory..."

declare -A router_commit

for router_id in "${all_router_ids[@]}"; do
  commit=$(yq eval ".routers[] | select (.id == \"${router_id}\") | .source.commit" "${IMAGES_YAML}" 2>/dev/null || echo "")

  if [ -n "${commit}" ]; then
    relay_commit["${relay_id}"]="${commit}"
  fi
done

indent
print_success "Loaded data for ${#all_relay_ids[@]} relays"
unindent
echo ""

# Load implementation data for all implementations
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

  # Load the relay associative arrays from serialized files
  declare -A relay_image_transports
  declare -A relay_image_secure
  declare -A relay_image_muxers
  declare -A relay_image_dial_only
  declare -A relay_image_commit

  while IFS='|' read -r key value; do
    relay_image_transports["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/relay-transports.dat"

  while IFS='|' read -r key value; do
    relay_image_secure["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/relay-secure.dat"

  while IFS='|' read -r key value; do
    relay_image_muxers["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/relay-muxers.dat"

  if [ -f "${WORKER_DATA_DIR}/relay-dial-only.dat" ]; then
    while IFS='|' read -r key value; do
      relay_image_dial_only["${key}"]="${value}"
    done < "${WORKER_DATA_DIR}/relay-dial-only.dat"
  fi

  if [ -f "${WORKER_DATA_DIR}/relay-commits.dat" ]; then
    while IFS='|' read -r key value; do
      relay_image_commit["${key}"]="${value}"
    done < "${WORKER_DATA_DIR}/relay-commits.dat"
  fi

  # Load the router associative arrays from serialized files
  declare -A router_image_commit

  if [ -f "${WORKER_DATA_DIR}/router-commits.dat" ]; then
    while IFS='|' read -r key value; do
      router_image_commit["${key}"]="${value}"
    done < "${WORKER_DATA_DIR}/router-commits.dat"
  fi

  # Load image associative arrays from serialized files
  declare -A image_transports
  declare -A image_secure
  declare -A image_muxers
  declare -A image_dial_only
  declare -A image_commit

  while IFS='|' read -r key value; do
    image_transports["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/image-transports.dat"

  while IFS='|' read -r key value; do
    image_secure["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/image-secure.dat"

  while IFS='|' read -r key value; do
    image_muxers["${key}"]="${value}"
  done < "${WORKER_DATA_DIR}/image-muxers.dat"

  if [ -f "${WORKER_DATA_DIR}/image-dial-only.dat" ]; then
    while IFS='|' read -r key value; do
      image_dial_only["${key}"]="${value}"
    done < "${WORKER_DATA_DIR}/image-dial-only.dat"
  fi

  if [ -f "${WORKER_DATA_DIR}/image-commits.dat" ]; then
    while IFS='|' read -r key value; do
      image_commit["${key}"]="${value}"
    done < "${WORKER_DATA_DIR}/image-commits.dat"
  fi

  # Iterate through all relays
  for relay_id in "${all_relay_ids[@]}"; do
    relay_transports="${relay_image_transports[${relay_id}]}"
    relay_secure="${relay_image_secure[${relay_id}]}"
    relay_muxers="${relay_image_muxers[${relay_id}]}"

    relay_selected=true

    if [[ ! " ${filtered_relay_ids[*]} " =~ " ${relay_id} " ]]; then
      print_debug "${relay_id} is an ignored relay id"
      relay_selected=false
    fi
    print_debug "selecting relay: ${relay_id}"

    # Iterate through all dialer routers
    for dialer_router_id in "${all_router_ids[@]}"; do
      dialer_router_selected=true

      if [[ ! " ${filtered_router_ids[*]} " =~ " ${dialer_router_id} " ]]; then
        print_debug "${dialer_router_id} is an ignored router id"
        dialer_router_selected=false
      fi

      print_debug "selecting dialer router: ${dialer_router_id}"

      # Iterate through all listener routers
      for listener_router_id in "${all_router_ids[@]}"; do
        listener_router_selected=true

        if [[ ! " ${filtered_router_ids[*]} " =~ " ${listener_router_id} " ]]; then
          print_debug "${listener_router_id} is an ignored router id"
          listener_router_selected=false
        fi

        print_debug "selecting listener router: ${listener_router_id}"

        # Iterate through all dialers
        for dialer_id in "${all_image_ids[@]}"; do
          dialer_transports="${image_transports[$dialer_id]}"
          dialer_secure="${image_secure[$dialer_id]}"
          dialer_muxers="${image_muxers[$dialer_id]}"

          dialer_selected=true

          if [[ ! " ${filtered_image_ids[*]} " =~ " ${dialer_id} " ]]; then
            print_debug "${dialer_id} is an ignored implementation id"
            dialer_selected=false
          fi

          print_debug "selecting dialer: ${dialer_id}"

          # Iterate through all listeners
          for listener_id in "${filtered_image_ids[@]}"; do
            listener_transports="${image_transports[${listener_id}]}"
            listener_secure="${image_secure[${listener_id}]}"
            listener_muxers="${image_muxers[${listener_id}]}"

            listener_selected=true

            if [[ ! " ${filtered_image_ids[*]} " =~ " ${listener_id} " ]]; then
              print_debug "${listener_id} is an ignored implementation id"
              listener_selected=false
            fi

            print_debug "selecting listener: ${listener_id}"

            # Find common transports
            common_transports=$(get_common "$relay_transports" "$dialer_transports" "$listener_transports")

            # Skip if no common transports
            [ -z "$common_transports" ] && continue

            # Process each common transport
            for transport in $common_transports; do
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

              print_debug "selecting transport: ${transport}"

              # Get commits for snapshot references
              local dialer_commit="${image_commit[${dialer_id}]:-}"
              local listener_commit="${image_commit[${listener_id}]:-}"
              local relay_commit="${relay_commit[${relay_id}]:-}"
              local dialer_router_commit="${router_image_commit[${dialer_router_id}]:-}"
              local listener_router_commit="${router_image_commit[${listener_router_id}]:-}"

              if is_standalone_transport "$transport"; then

                # Integrated transport with built-in secure channel and muxer
                test_id="${dialer_id} x ${listener_id} (${transport}) [dr: ${dialer_router_id}, rly: ${relay_id}, lr: ${listener_router_id}]"
                # Add to selected or ignored list
                if [ "${dialer_selected}" == "true" ] && \
                   [ "${listener_selected}" == "true" ] && \
                   [ "${relay_selected}" == "true" ] && \
                   [ "${dialer_router_selected}" == "true" ] && \
                   [ "${listener_router_selected}" == "true" ] && \
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
EOF
                  if [ -n "${dialer_commit}" ]; then
                    echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_selected}"
                  fi
                  cat >> "${worker_selected}" <<EOF
    listener:
      id: ${listener_id}
EOF
                  if [ -n "${listener_commit}" ]; then
                    echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_selected}"
                  fi
                  cat >> "${worker_selected}" <<EOF
    relay:
      id: ${relay_id}
EOF
                  if [ -n "${relay_commit}" ]; then
                    echo "      snapshot: snapshots/${relay_commit}.zip" >> "${worker_selected}"
                  fi
                  cat >> "${worker_selected}" <<EOF
    dialerRouter:
      id: ${dialer_router_id}
EOF
                  if [ -n "${dialer_router_commit}" ]; then
                    echo "      snapshot: snapshots/${dialer_router_commit}.zip" >> "${worker_selected}"
                  fi
                  cat >> "${worker_selected}" <<EOF
    listenerRouter:
      id: ${listener_router_id}
EOF
                  if [ -n "${listener_router_commit}" ]; then
                    echo "      snapshot: snapshots/${listener_router_commit}.zip" >> "${worker_selected}"
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
EOF
                  if [ -n "${dialer_commit}" ]; then
                    echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_ignored}"
                  fi
                  cat >> "${worker_ignored}" <<EOF
    listener:
      id: ${listener_id}
EOF
                  if [ -n "${listener_commit}" ]; then
                    echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_ignored}"
                  fi
                  cat >> "${worker_ignored}" <<EOF
    relay:
      id: ${relay_id}
EOF
                  if [ -n "${relay_commit}" ]; then
                    echo "      snapshot: snapshots/${relay_commit}.zip" >> "${worker_selected}"
                  fi
                  cat >> "${worker_ignored}" <<EOF
    dialerRouter:
      id: ${dialer_router_id}
EOF
                  if [ -n "${dialer_router_commit}" ]; then
                    echo "      snapshot: snapshots/${dialer_router_commit}.zip" >> "${worker_selected}"
                  fi
                  cat >> "${worker_ignored}" <<EOF
    listenerRouter:
      id: ${listener_router_id}
EOF
                  if [ -n "${listener_router_commit}" ]; then
                    echo "      snapshot: snapshots/${listener_router_commit}.zip" >> "${worker_selected}"
                  fi
                fi

              else

                # Find common secure channels and muxers
                common_secure=$(get_common "$dialer_secure" "$listener_secure")
                common_muxers=$(get_common "$dialer_muxers" "$listener_muxers")

                # Skip if no common secure channels or muxers
                [ -z "$common_secure" ] && continue
                [ -z "$common_muxers" ] && continue

                # Generate all valid combinations
                for secure in $common_secure; do

                  secure_selected=true

                  if [[ ! " ${filtered_secure_names[*]} " =~ " ${secure} " ]]; then
                    print_debug "${secure} is an ignored secure channel"
                    secure_selected=false
                  fi

                  print_debug "selecting secure channel: ${secure}"

                  for muxer in $common_muxers; do

                    muxer_selected=true

                    if [[ ! " ${filtered_muxer_names[*]} " =~ " ${muxer} " ]]; then
                      print_debug "${muxer} is an ignored muxer"
                      secure_selected=false
                    fi

                    print_debug "selecting muxer: ${muxer}"

                    test_name="$dialer_id x $listener_id ($transport, $secure, $muxer) [dr: $dialer_router_id, rly: $relay_id, lr: $listener_router_id]"
                    # Add to selected or ignored list
                    if [ "${dialer_selected}" == "true" ] && \
                       [ "${listener_selected}" == "true" ] && \
                       [ "${relay_selected}" == "true" ] && \
                       [ "${dialer_router_selected}" == "true" ] && \
                       [ "${listener_router_selected}" == "true" ] && \
                       [ "${transport_selected}" == "true" ] && \
                       [ "${secure_selected}" == "true" ] && \
                       [ "${muxer_selected}" == "true" ]; then

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
EOF
                      if [ -n "${dialer_commit}" ]; then
                        echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_selected}"
                      fi
                      cat >> "${worker_selected}" <<EOF
    listener:
      id: ${listener_id}
EOF
                      if [ -n "${listener_commit}" ]; then
                        echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_selected}"
                      fi
                      cat >> "${worker_selected}" <<EOF
    relay:
      id: ${relay_id}
EOF
                      if [ -n "${relay_commit}" ]; then
                        echo "      snapshot: snapshots/${relay_commit}.zip" >> "${worker_selected}"
                      fi
                      cat >> "${worker_selected}" <<EOF
    dialerRouter:
      id: ${dialer_router_id}
EOF
                      if [ -n "${dialer_router_commit}" ]; then
                        echo "      snapshot: snapshots/${dialer_router_commit}.zip" >> "${worker_selected}"
                      fi
                      cat >> "${worker_selected}" <<EOF
    listenerRouter:
      id: ${listener_router_id}
EOF
                      if [ -n "${listener_router_commit}" ]; then
                        echo "      snapshot: snapshots/${listener_router_commit}.zip" >> "${worker_selected}"
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
EOF
                      if [ -n "${dialer_commit}" ]; then
                        echo "      snapshot: snapshots/${dialer_commit}.zip" >> "${worker_ignored}"
                      fi
                      cat >> "${worker_ignored}" <<EOF
    listener:
      id: ${listener_id}
EOF
                      if [ -n "${listener_commit}" ]; then
                        echo "      snapshot: snapshots/${listener_commit}.zip" >> "${worker_ignored}"
                      fi
                      cat >> "${worker_ignored}" <<EOF
    relay:
      id: ${relay_id}
EOF
                      if [ -n "${relay_commit}" ]; then
                        echo "      snapshot: snapshots/${relay_commit}.zip" >> "${worker_selected}"
                      fi
                      cat >> "${worker_ignored}" <<EOF
    dialerRouter:
      id: ${dialer_router_id}
EOF
                      if [ -n "${dialer_router_commit}" ]; then
                        echo "      snapshot: snapshots/${dialer_router_commit}.zip" >> "${worker_selected}"
                      fi
                      cat >> "${worker_ignored}" <<EOF
    listenerRouter:
      id: ${listener_router_id}
EOF
                      if [ -n "${listener_router_commit}" ]; then
                        echo "      snapshot: snapshots/${listener_router_commit}.zip" >> "${worker_selected}"
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
}

# Serialize the relay associative arrays to temp files for workers
# (Bash can't export associative array contents to subshells)
WORKER_DATA_DIR="${TEST_PASS_DIR}/worker-data"
mkdir -p "${WORKER_DATA_DIR}"
print_debug "WORKER_DATA_DIR: ${WORKER_DATA_DIR}" 

# Serialize relay data
for key in "${!relay_transports[@]}"; do
  echo "${key}|${relay_transports[${key}]}" >> "${WORKER_DATA_DIR}/relay-transports.dat"
done

for key in "${!relay_secure[@]}"; do
  echo "${key}|${relay_secure[${key}]}" >> "${WORKER_DATA_DIR}/relay-secure.dat"
done

for key in "${!relay_muxers[@]}"; do
  echo "${key}|${relay_muxers[${key}]}" >> "${WORKER_DATA_DIR}/relay-muxers.dat"
done

for key in "${!relay_dial_only[@]}"; do
  echo "${key}|${relay_dial_only[${key}]}" >> "${WORKER_DATA_DIR}/relay-dial-only.dat"
done

for key in "${!relay_commit[@]}"; do
  echo "${key}|${relay_commit[${key}]}" >> "${WORKER_DATA_DIR}/relay-commits.dat"
done

# Serialize router data
for key in "${!router_commit[@]}"; do
  echo "${key}|${router_commit[${key}]}" >> "${WORKER_DATA_DIR}/router-commits.dat"
done

# Serialize image data
for key in "${!image_transports[@]}"; do
  echo "${key}|${image_transports[${key}]}" >> "${WORKER_DATA_DIR}/image-transports.dat"
done

for key in "${!image_secure[@]}"; do
  echo "${key}|${image_secure[${key}]}" >> "${WORKER_DATA_DIR}/image-secure.dat"
done

for key in "${!image_muxers[@]}"; do
  echo "${key}|${image_muxers[${key}]}" >> "${WORKER_DATA_DIR}/image-muxers.dat"
done

for key in "${!image_dial_only[@]}"; do
  echo "${key}|${image_dial_only[${key}]}" >> "${WORKER_DATA_DIR}/image-dial-only.dat"
done

for key in "${!image_commit[@]}"; do
  echo "${key}|${image_commit[${key}]}" >> "${WORKER_DATA_DIR}/image-commits.dat"
done

# Export necessary variables and functions for workers
export -f generate_tests_worker
export -f get_common
export -f is_standalone_transport
export -f print_debug
export -f get_source_commit
export -f get_source_type
export TEST_PASS_DIR
export WORKER_DATA_DIR
export filtered_relay_ids
export filtered_router_ids
export filtered_image_ids
export all_relay_ids
export all_router_ids
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
  relayIgnore: |-
    ${RELAY_IGNORE}
  routerIgnore: |-
    ${ROUTER_IGNORE}
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
