#!/bin/bash
# Common library for saving Docker images in snapshots
# Used by create-snapshot.sh in transport, hole-punch, and perf

# Source formatting library if not already loaded
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$_this_script_dir/lib-output-formatting.sh"
fi

# Save all Docker images needed for tests
# Usage: save_docker_images_for_tests <snapshot_dir> <test_type>
# test_type: "transport", "hole-punch", or "perf"
save_docker_images_for_tests() {
  local snapshot_dir="$1"
  local test_type="$2"
  indent

  # Collect all unique image names needed
  declare -A unique_images

  # Get unique implementations (all test types use .dialer and .listener)
  while read -r impl_id; do
    if [ -n "$impl_id" ] && [ "$impl_id" != "null" ]; then
      local img_name=$(get_impl_image_name "$impl_id" "$test_type")
      unique_images["$img_name"]=1
    fi
  done < <(yq eval '.tests[] | [.dialer.id, .listener.id][]' "$snapshot_dir/test-matrix.yaml" | sort -u)

  # For perf, also get baseline implementations
  if [ "$test_type" == "perf" ]; then
    while read -r impl_id; do
      if [ -n "$impl_id" ] && [ "$impl_id" != "null" ]; then
        local img_name=$(get_impl_image_name "$impl_id" "$test_type")
        unique_images["$img_name"]=1
      fi
    done < <(yq eval '.baselines[] | [.dialer.id, .listener.id][]' "$snapshot_dir/test-matrix.yaml" 2>/dev/null | sort -u)
  fi

  # For hole-punch tests, also collect relays and routers
  if [ "$test_type" == "hole-punch" ]; then
    # Get unique relays
    while read -r relay_id; do
      if [ -n "$relay_id" ]; then
        local img_name=$(get_relay_image_name "$relay_id" "$test_type")
        unique_images["$img_name"]=1
      fi
    done < <(yq eval '.tests[].relay' "$snapshot_dir/test-matrix.yaml" | sort -u)

    # Get unique routers
    while read -r router_id; do
      if [ -n "$router_id" ]; then
        local img_name=$(get_router_image_name "$router_id" "$test_type")
        unique_images["$img_name"]=1
      fi
    done < <(yq eval '.tests[] | [.dialerRouter, .listenerRouter][]' "$snapshot_dir/test-matrix.yaml" | sort -u)
  fi

  # Also add base images for browser-type implementations (transport only)
  if [ "$test_type" == "transport" ]; then
    local impl_count=$(yq eval '.implementations | length' images.yaml)
    for ((i=0; i<impl_count; i++)); do
      local impl_id=$(yq eval ".implementations[$i].id" images.yaml)
      local source_type=$(yq eval ".implementations[$i].source.type" images.yaml)

      # Check if this implementation is used in tests
      if echo "${!unique_images[@]}" | grep -q "transport-interop-${impl_id}"; then
        # If it's a browser type, add its base image
        if [ "$source_type" == "browser" ]; then
          local base_image=$(yq eval ".implementations[$i].source.baseImage" images.yaml)
          if [ -n "$base_image" ] && [ "$base_image" != "null" ]; then
            local base_img_name=$(get_impl_image_name "$base_image" "$test_type")
            unique_images["$base_img_name"]=1
          fi
        fi
      fi
    done
  fi

  # Count total images to save
  local total_images=${#unique_images[@]}
    local current_image=0

    print_message "Found $total_images images to save"
    print_message "Note: Each image save may take 1-5 minutes depending on size"

    # Save each image
    for image_name in "${!unique_images[@]}"; do
      if docker image inspect "$image_name" &> /dev/null; then
        local image_file="$snapshot_dir/docker-images/${image_name}.tar.gz"
        if [ ! -f "$image_file" ]; then
          current_image=$((current_image + 1))
          indent
          echo_message "[$current_image/$total_images] Saving: $image_name..."
          docker save "$image_name" | gzip > "$image_file"
          local saved_size=$(du -h "$image_file" | cut -f1)
          echo "[SAVED $saved_size]"
          unindent
        else
          print_message "Skipping $image_name (already saved)"
        fi
      else
        print_error "Image not found: $image_name (will need to rebuild on re-run)"
      fi
    done
    echo ""

    print_success "All docker images processed"
    unindent
  }
