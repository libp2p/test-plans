#!/bin/bash
# Generate test matrix from images.yaml with filtering
# Outputs test-matrix.yaml with content-addressed caching
# Permutations: dialer × listener × transport × secureChannel × muxer × relay × dialer_router × listener_router

##### 1. SETUP

set -uo pipefail  # Removed -e to allow continuation on errors

# Set SCRIPT_LIB_DIR if not already set (for snapshot context)
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib}"

# Source common libraries
source "$SCRIPT_LIB_DIR/lib-filter-engine.sh"
source "$SCRIPT_LIB_DIR/lib-generate-tests.sh"
source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"
source "$SCRIPT_LIB_DIR/lib-test-aliases.sh"
source "$SCRIPT_LIB_DIR/lib-test-caching.sh"
source "$SCRIPT_LIB_DIR/lib-test-filtering.sh"

##### 2. PARAMETER INITIALIZATION

# Common parameters
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_SELECT="${TEST_SELECT:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
DEBUG="${DEBUG:-false}"
FORCE_MATRIX_REBUILD="${FORCE_MATRIX_REBUILD:-false}"
OUTPUT_DIR="${TEST_PASS_DIR:-.}"  # Use TEST_PASS_DIR if set, otherwise current directory

# Hole Punch parameters
RELAY_SELECT="${RELAY_SELECT:-}"
RELAY_IGNORE="${RELAY_IGNORE:-}"
ROUTER_SELECT="${ROUTER_SELECT:-}"
ROUTER_IGNORE="${ROUTER_IGNORE:-}"

##### 3. FILTER EXPANSION

# Load test aliases from images.yaml
load_aliases

# Get common entity IDs for negation expansion and ignored test generation
all_image_ids=($(get_entity_ids "implementations"))

# Hole Punch entity IDs
all_relay_ids=($(get_entity_ids "relays"))
all_router_ids=($(get_entity_ids "routers"))

# Save original filters for display
ORIGINAL_TEST_SELECT="$TEST_SELECT"
ORIGINAL_TEST_IGNORE="$TEST_IGNORE"
ORIGINAL_RELAY_SELECT="$RELAY_SELECT"
ORIGINAL_RELAY_IGNORE="$RELAY_IGNORE"
ORIGINAL_ROUTER_SELECT="$ROUTER_SELECT"
ORIGINAL_ROUTER_IGNORE="$ROUTER_IGNORE"

# Expand filters explicitly so we can display the expansions
if [ -n "$TEST_SELECT" ]; then
  EXPANDED_TEST_SELECT=$(expand_filter_string "$TEST_SELECT" all_image_ids)
else
  EXPANDED_TEST_SELECT=""
fi

if [ -n "$TEST_IGNORE" ]; then
  EXPANDED_TEST_IGNORE=$(expand_filter_string "$TEST_IGNORE" all_image_ids)
else
  EXPANDED_TEST_IGNORE=""
fi

if [ -n "$RELAY_SELECT" ]; then
  EXPANDED_RELAY_SELECT=$(expand_filter_string "$RELAY_SELECT" all_relay_ids)
else
  EXPANDED_RELAY_SELECT=""
fi

if [ -n "$RELAY_IGNORE" ]; then
  EXPANDED_RELAY_IGNORE=$(expand_filter_string "$RELAY_IGNORE" all_relay_ids)
else
  EXPANDED_RELAY_IGNORE=""
fi

if [ -n "$ROUTER_SELECT" ]; then
  EXPANDED_ROUTER_SELECT=$(expand_filter_string "$ROUTER_SELECT" all_router_ids)
else
  EXPANDED_ROUTER_SELECT=""
fi

if [ -n "$ROUTER_IGNORE" ]; then
  EXPANDED_ROUTER_IGNORE=$(expand_filter_string "$ROUTER_IGNORE" all_router_ids)
else
  EXPANDED_ROUTER_IGNORE=""
fi

##### 4. DISPLAY FILTER EXPANSION

# test select
print_filter_expansion \
  "ORIGINAL_TEST_SELECT" \
  "EXPANDED_TEST_SELECT" \
  "Test select" \
  "No test-select specified (will include all implementations)"

# test ignore
print_filter_expansion \
  "ORIGINAL_TEST_IGNORE" \
  "EXPANDED_TEST_IGNORE" \
  "Test ignore" \
  "No test-ignore specified (will ignore none)"

# relay select
print_filter_expansion \
  "ORIGINAL_RELAY_SELECT" \
  "EXPANDED_RELAY_SELECT" \
  "Relay select" \
  "No relay-select specified (will include all relays)"

# relay ignore
print_filter_expansion \
  "ORIGINAL_RELAY_IGNORE" \
  "EXPANDED_RELAY_IGNORE" \
  "Relay ignore" \
  "No relay-ignore specified (will ignore none)"

# router select
print_filter_expansion \
  "ORIGINAL_ROUTER_SELECT" \
  "EXPANDED_ROUTER_SELECT" \
  "Router select" \
  "No router-select specified (will include all routers)"

# relay ignore
print_filter_expansion \
  "ORIGINAL_ROUTER_IGNORE" \
  "EXPANDED_ROUTER_IGNORE" \
  "Router ignore" \
  "No router-ignore specified (will ignore none)"

echo ""

##### 5. CACHE CHECK AND EARLY EXIT

# Use TEST_RUN_KEY from parent (run.sh) if available
# Otherwise compute cache key from images.yaml + all filters + debug
if [ -n "${TEST_RUN_KEY:-}" ]; then
  cache_key="$TEST_RUN_KEY"
  print_message "Using test run key: $cache_key"
else
  # Fallback for standalone execution
  cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "$RELAY_SELECT" "$RELAY_IGNORE" "$ROUTER_SELECT" "$ROUTER_IGNORE" "$DEBUG")
  print_message "Computed cache key: ${cache_key:0:8}"
fi

# Check cache (with optional force rebuild)
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$OUTPUT_DIR" "$FORCE_MATRIX_REBUILD" "hole-punch"; then
  exit 0
fi

echo ""

##### 6. FILTERING

# Filter all three entity types upfront using global filter_entity_list function
print_message "Filtering implementations..."
mapfile -t filtered_image_ids < <(filter_ids all_image_ids "$TEST_SELECT" "$TEST_IGNORE")
indent
print_success "Filtered to ${#filtered_image_ids[@]} implementations (${#all_image_ids[@]} total)"
unindent

print_message "Filtering relays..."
mapfile -t filtered_relay_ids < <(filter_ids all_relay_ids "$RELAY_SELECT" "$RELAY_IGNORE")
indent
print_success "Filtered to ${#filtered_relay_ids[@]} relays (${#all_relay_ids[@]} total)"
unindent

echo "→ Filtering routers..."
mapfile -t filtered_router_ids < <(filter_entity_list "routers" "$ROUTER_SELECT" "$ROUTER_IGNORE")
indent
print_success "Filtered to ${#filtered_router_ids[@]} routers (${#all_router_ids[@]} total)"
unindent

echo ""

##### 7. LOAD PARAMETER LISTS

# Load implementation data only for filtered implementations
print_message "Loading implementation data into memory..."

declare -A image_transports    # image_transports[linux]="tcp quic-v1"
declare -A image_secure        # image_secure[linux]="noise tls"
declare -A image_muxers        # image_muxers[linux]="yamux mplex"
declare -A image_dial_only     # image_dial_only[linux]="webtransport"

for image_id in "${filtered_image_ids[@]}"; do
  transports=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .transports | join(\" \")" images.yaml)
  secure=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .secureChannels | join(\" \")" images.yaml)
  muxers=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .muxers | join(\" \")" images.yaml)
  dial_only=$(yq eval ".implementations[] | select(.id == \"$image_id\") | .dialOnly | join(\" \")" images.yaml 2>/dev/null || echo "")

  image_transports["$image_id"]="$transports"
  image_secure["$image_id"]="$secure"
  image_muxers["$image_id"]="$muxers"
  image_dial_only["$image_id"]="$dial_only"
done

indent
print_success "Loaded data for ${#filtered_image_ids[@]} filtered implementations"
unindent

echo ""

##### 8. GENERATE TEST MATRIX

# Initialize test lists
tests=()
test_num=0
ignored_tests=()
ignored_test_num=0

print_header "Generating test combinations..."

# Iterate through all combinations
for relay_id in "${all_relay_ids[@]}"; do
  for dialer_router_id in "${all_router_ids[@]}"; do
    for listener_router_id in "${all_router_ids[@]}"; do
      for dialer_id in "${all_image_ids[@]}"; do
        dialer_transports="${image_transports[$dialer_id]}"
        dialer_secure="${image_secure[$dialer_id]}"
        dialer_muxers="${image_muxers[$dialer_id]}"

        for listener_id in "${filtered_image_ids[@]}"; do
          # Check if BOTH the dialer and listener are in the filtered images list,
          # as well as the relay being in the filtered relay list and BOTH the dialer
          # router and listener router in the filtered routers list
          test_is_selected=false
          if [[ " ${filtered_image_ids[*]} " =~ " ${dialer_id} " ]] && \
             [[ " ${filtered_image_ids[*]} " =~ " ${listener_id} " ]] && \
             [[ " ${filtered_relay_ids[*]} " =~ " ${relay_id} "]] && \
             [[ " ${filtered_router_ids[*]} " =~ " ${dialer_router_id} "]] && \
             [[ " ${filtered_router_ids[*]} " =~ " ${listener_router_id} "]]; then
            test_is_selected=true
          fi

          listener_transports="${image_transports[$listener_id]}"
          listener_secure="${image_secure[$listener_id]}"
          listener_muxers="${image_muxers[$listener_id]}"

          # Find common transports
          common_transports=$(get_common "$dialer_transports" "$listener_transports")

          # Skip if no common transports
          [ -z "$common_transports" ] && continue

          # Process each common transport
          for transport in $common_transports; do
            # Check if LISTENER IMPLEMENTATION can handle this transport
            if ! can_be_listener_for_transport "$listener_id" "$transport" "$image_dial_only"; then
              continue  # Skip: listener implementation has this transport in dialOnly
            fi

            if is_standalone_transport "$transport"; then
              # Standalone transport (no secure/muxer needed)
              test_name="$dialer_id x $listener_id ($transport) [dr: $dialer_router_id, rly: $relay_id, lr: $listener_router_id]"

              # Add to selected or ignored list based on entity membership
              if [ "$test_is_selected" == "true" ]; then
                # Add to selected tests
                tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null|$relay_id|$dialer_router_id|$listener_router_id")
                ((test_num++))
              else
                # Add to ignored tests
                ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|null|null|$relay_id|$dialer_router_id|$listener_router_id")
                ((ignored_test_num++))
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
                  test_name="$dialer_id x $listener_id ($transport, $secure, $muxer) [dr: $dialer_router_id, rly: $relay_id, lr: $listener_router_id]"

                  # Add to selected or ignored list based on entity membership
                  if [ "$test_is_selected" == "true" ]; then
                    # Add to selected tests
                    tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer|$relay_id|$dialer_router_id|$listener_router_id")
                    ((test_num++))
                  else
                    ignored_tests+=("$test_name|$dialer_id|$listener_id|$transport|$secure|$muxer|$relay_id|$dialer_router_id|$listener_router_id")
                    ((ignored_test_num++))
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

print_success "Generated ${#tests[@]} tests"

echo ""

##### 9. OUTPUT TEST MATRIX

output_tests() {
  local name=$1
  local tests=$2

  cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF

$name:
EOF

  for test in "${tests[@]}"; do
    IFS='|' read -r name dialer listener transport secure muxer relay_id dialer_router_id listener_router_id <<< "$test"

    # Get commits, treating null/empty as local
    dialer_commit=$(yq eval ".implementations[] | select(.id == \"$dialer\") | .source.commit" images.yaml 2>/dev/null || echo "local")
    listener_commit=$(yq eval ".implementations[] | select(.id == \"$listener\") | .source.commit" images.yaml 2>/dev/null || echo "local")

    # Normalize null values to "local"
    [ "$dialer_commit" == "null" ] && dialer_commit="local"
    [ "$listener_commit" == "null" ] && listener_commit="local"

      cat >> "$OUTPUT_DIR/test-matrix.yaml" <<EOF
  - name: "$name"
    dialer: $dialer
    listener: $listener
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    dialerRouter: $dialer_router_id
    relay: $relay_id
    listenerRouter: $listener_router_id
EOF

    # Only add snapshot fields for non-local sources
    if [ "$dialer_commit" != "local" ]; then
      echo "    dialerSnapshot: snapshots/$dialer_commit.zip" >> "$OUTPUT_DIR/test-matrix.yaml"
    fi
    if [ "$listener_commit" != "local" ]; then
      echo "    listenerSnapshot: snapshots/$listener_commit.zip" >> "$OUTPUT_DIR/test-matrix.yaml"
    fi
  done
}



# Generate test-matrix.yaml
cat > "$OUTPUT_DIR/test-matrix.yaml" <<EOF
metadata:
  generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  select: $TEST_SELECT
  ignore: $TEST_IGNORE
  relaySelect: $RELAY_SELECT
  relayIgnore: $RELAY_IGNORE
  routerSelect: $ROUTER_SELECT
  routerIgnore: $ROUTER_IGNORE
  totalTests: ${#tests[@]}
  ignoredTests: 0
  debug: $DEBUG
EOF

# output selected tests
output_tests "test" "$tests"

# output ignored tests
output_tests "ignoredTests" "$ignored_tests"

# Cache the generated matrix
save_to_cache "$OUTPUT_DIR" "$cache_key" "$CACHE_DIR" "hole-punch"

echo ""
print_success "Generated test matrix with ${#tests[@]} tests"
