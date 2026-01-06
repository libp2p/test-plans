#!/bin/bash
# Utilities for loading values from the images.yaml file

# Load aliases from images.yaml into an associative array
# This populates the global ALIASES array used by filter functions
#
# Args:
#   $1: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   Populates global ALIASES associative array
# Usage:
#   load_aliases
#   load_aliases "custom-images.yaml"
load_aliases() {
  local images_file="${1:-images.yaml}"
  declare -gA ALIASES  # Global associative array

  if [ ! -f "$images_file" ]; then
    return
  fi

  # Check if test-aliases exists
  local alias_count=$(yq eval '.test-aliases | length' "$images_file" 2>/dev/null || echo 0)

  if [ "$alias_count" -eq 0 ] || [ "$alias_count" = "null" ]; then
    return
  fi

  # Load each alias
  for ((i=0; i<alias_count; i++)); do
    local alias_name=$(yq eval ".test-aliases[$i].alias" "$images_file")
    local alias_value=$(yq eval ".test-aliases[$i].value" "$images_file")
    ALIASES["$alias_name"]="$alias_value"
  done
}

# Generic function to get all entity IDs from images.yaml
# Works for any entity type: implementations, baselines, relays, routers, etc.
#
# Args:
#   $1: entity_type - Entity type key in images.yaml (e.g., "implementations", "baselines", "relays")
#   $2: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   Array of entity IDs (one per line)
# Usage:
#   all_impl_ids=($(get_entity_ids "implementations"))
#   all_baseline_ids=($(get_entity_ids "baselines"))
#   all_relay_ids=($(get_entity_ids "relays" "custom-images.yaml"))
get_entity_ids() {
  local entity_type="$1"
  local images_file="${2:-images.yaml}"

  if [ ! -f "$images_file" ]; then
    return 0
  fi

  yq eval ".${entity_type}[].id" "$images_file" 2>/dev/null
}

# Generic function to get all unique transport names from images.yaml
# Works for any entity type: implementations, baselines, relays, routers, etc.
#
# Args:
#   $1: entity_type - Entity type key in images.yaml (e.g., "implementations", "baselines", "relays")
#   $2: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   Array of transport names (one per line)
# Usage:
#   all_transport_names=($(get_transport_names "implementations"))
#   all_relay_transport_names=($(get_transport_names "relays" "custom-images.yaml"))
get_transport_names() {
  local entity_type="$1"
  local images_file="${2:-images.yaml}"

  if [ ! -f "$images_file" ]; then
    return 0
  fi

  yq eval ".${entity_type}[].transports[]" "$images_file" 2>/dev/null | sort -u
}

# Generic function to get all unique secure channel names from images.yaml
# Works for any entity type: implementations, baselines, relays, routers, etc.
#
# Args:
#   $1: entity_type - Entity type key in images.yaml (e.g., "implementations", "baselines", "relays")
#   $2: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   Array of secure channel names (one per line)
# Usage:
#   all_secure_names=($(get_secure_names "implementations"))
#   all_relay_secure_names=($(get_secure_names "relays" "custom-images.yaml"))
get_secure_names() {
  local entity_type="$1"
  local images_file="${2:-images.yaml}"

  if [ ! -f "$images_file" ]; then
    return 0
  fi

  yq eval ".${entity_type}[].secureChannels[]" "$images_file" 2>/dev/null | sort -u
}

# Generic function to get all unique muxer names from images.yaml
# Works for any entity type: implementations, baselines, relays, routers, etc.
#
# Args:
#   $1: entity_type - Entity type key in images.yaml (e.g., "implementations", "baselines", "relays")
#   $2: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   Array of muxer names (one per line)
# Usage:
#   all_muxer_names=($(get_muxer_names "implementations"))
#   all_relay_muxer_names=($(get_muxer_names "relays" "custom-images.yaml"))
get_muxer_names() {
  local entity_type="$1"
  local images_file="${2:-images.yaml}"

  if [ ! -f "$images_file" ]; then
    return 0
  fi

  yq eval ".${entity_type}[].muxers[]" "$images_file" 2>/dev/null | sort -u
}

# Generic function to get the source type for the given entity_type and id
# Works for any entity type: implementations, baselines, relays, routers, etc.
#
# Args:
#   $1: entity_type - Entity type key in images.yaml (e.g., "implementations", "baselines", "relays")
#   $2: id - The id of the entity (e.g. "rust-v0.56")
#   $3: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   The source type for the given entity_type and id (e.g. "local", "github")
# Usage:
#   impl_source_type=($(get_source_type "implementations" "rust-v0.56"))
#   relay_source_type=($(get_source_type "relays" "linux-relay" "custom-images.yaml"))
get_source_type() {
  local entity_type="$1"
  local id="$2"
  local images_file="${3:-images.yaml}"

  if [ ! -f "$images_file" ]; then
    return 0
  fi
 
  # Get the entity_type's source type
  yq eval ".${entity_type}[] | select(.id == \"$id\") | .source.type" "$images_file" 2>/dev/null || echo "local"
}

# Generic function to get the source commit for the given entity_type and id
# Works for any entity type: implementations, baselines, relays, routers, etc.
#
# Args:
#   $1: entity_type - Entity type key in images.yaml (e.g., "implementations", "baselines", "relays")
#   $2: id - The id of the entity (e.g. "rust-v0.56")
#   $3: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   The source commit SHA1 for the given entity_type and id
# Usage:
#   impl_source_commit=($(get_source_commit "implementations" "rust-v0.56"))
#   relay_source_commit=($(get_source_commit "relays" "linux-relay" "custom-images.yaml"))
get_source_commit() {
  local entity_type="$1"
  local id="$2"
  local images_file="${3:-images.yaml}"

  if [ ! -f "$images_file" ]; then
    return 0
  fi

  # Get the source type
  local source_type=$(get_source_type "$entity_type" "$id" "$images_file")

  # Only get the commit sha for "github" source types
  if [ "$source_type" != "local" ]; then
    yq eval ".${entity_type}[] | select(.id == \"$id\") | .source.commit" "$images_file" 2>/dev/null || echo ""
  else
    echo ""
  fi
}
