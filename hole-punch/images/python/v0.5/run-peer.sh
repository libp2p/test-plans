#!/usr/bin/env bash
set -e

# Set route to WAN subnet via router (required for NAT traversal)
if [ -n "${WAN_SUBNET}" ] && [ -n "${WAN_ROUTER_IP}" ]; then
    echo "Setting route to WAN subnet ${WAN_SUBNET} via ${WAN_ROUTER_IP}" >&2
    ip route add "${WAN_SUBNET}" via "${WAN_ROUTER_IP}" dev lan0 || true
fi

exec python /app/peer.py "$@"
