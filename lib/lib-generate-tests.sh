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

