#!/usr/bin/env bash
set -e

# Set route to dialer subnet
echo "Setting route to dialer subnet ${DIALER_LAN_SUBNET} via ${DIALER_ROUTER_IP}" >&2
ip route add "${DIALER_LAN_SUBNET}" via "${DIALER_ROUTER_IP}" dev wan0

# Set route to listener subnet
echo "Setting route to listener subnet ${LISTENER_LAN_SUBNET} via ${LISTENER_ROUTER_IP}" >&2
ip route add "${LISTENER_LAN_SUBNET}" via "${LISTENER_ROUTER_IP}" dev wan0

# Execute the relay binary, passing through all arguments
exec /usr/local/bin/relay "$@"
