#!/bin/bash
# Common library for test matrix generation functions
# Shared across transport, hole-punch, and perf generate-tests.sh scripts

# Standalone transports (self-encrypted transports that don't need layered security)
STANDALONE_TRANSPORTS="quic quic-v1 webtransport webrtc webrtc-direct https"

# Check if transport is standalone (doesn't need muxer/secureChannel)
# Args:
#   $1: transport name
# Returns:
#   0 (success) if transport is standalone
#   1 (failure) if transport requires secureChannel and muxer
is_standalone_transport() {
    local transport="$1"
    echo "$STANDALONE_TRANSPORTS" | grep -qw "$transport"
}

# Check if a transport can be used with an implementation as listener
# Args:
#   $1: image id
#   $2: transport name
#   $3: list of dial-only images
# Returns:
#   0 (true) if transport can be used as listener
#   1 (false) if dialOnly
can_be_listener_for_transport() {
  local image_id="$1"
  local transport="$2"
  local image_dial_only="$3"
  local dial_only_transports="${image_dial_only[$image_id]:-}"

  # If no dialOnly restrictions, can always be listener
  [ -z "$dial_only_transports" ] && return 0

  # Check if transport is in dialOnly list
  case " $dial_only_transports " in
    *" $transport "*)
      return 1  # Cannot be listener for this transport
      ;;
  esac

  return 0  # Can be listener
}

