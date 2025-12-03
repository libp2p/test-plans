#!/bin/bash
# Linux NAT Router Configuration Script
# Configures iptables-based NAT between LAN and WAN networks

set -euo pipefail

echo "========================================"
echo "Linux NAT Router Configuration"
echo "========================================"

# Required environment variables
WAN_SUBNET="${WAN_SUBNET:-}"
WAN_IP="${WAN_IP:-}"
LAN_SUBNET="${LAN_SUBNET:-}"
LAN_IP="${LAN_IP:-}"
DELAY_MS="${DELAY_MS:-0}"

# Validate required variables
if [ -z "$WAN_SUBNET" ] || [ -z "$WAN_IP" ] || [ -z "$LAN_SUBNET" ] || [ -z "$LAN_IP" ]; then
    echo "ERROR: Missing required environment variables"
    echo "Required: WAN_SUBNET, WAN_IP, LAN_SUBNET, LAN_IP"
    echo "Optional: DELAY_MS (default: 0)"
    exit 1
fi

echo "Configuration:"
echo "  WAN Subnet:  $WAN_SUBNET"
echo "  WAN IP:      $WAN_IP"
echo "  LAN Subnet:  $LAN_SUBNET"
echo "  LAN IP:      $LAN_IP"
echo "  Delay:       ${DELAY_MS}ms"
echo ""

# Note: Kernel parameters (ip_forward, rp_filter) are configured via
# sysctls in docker-compose.yaml for proper container operation

# Find network interfaces
WAN_IF=""
LAN_IF=""

echo "Detecting network interfaces..."
for iface in $(ls /sys/class/net | grep -v "^lo$"); do
    # Get IP address for this interface (extract IP from "inet <IP>/<mask>" format)
    IP=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1 || echo "")

    if [ -z "$IP" ]; then
        continue
    fi

    # Check if this IP matches WAN or LAN
    if [ "$IP" = "$WAN_IP" ]; then
        WAN_IF="$iface"
        echo "  WAN interface: $WAN_IF ($WAN_IP)"
    elif [[ "$IP" == "$LAN_IP" ]] || [[ "$IP" =~ ^${LAN_IP%/*} ]]; then
        LAN_IF="$iface"
        echo "  LAN interface: $LAN_IF ($IP)"
    fi
done

if [ -z "$WAN_IF" ] || [ -z "$LAN_IF" ]; then
    echo "ERROR: Could not detect WAN and/or LAN interfaces"
    echo "Available interfaces:"
    ip addr show
    exit 1
fi

echo ""
echo "Configuring iptables NAT rules..."

# Flush existing rules
iptables -t nat -F
iptables -t filter -F
iptables -t mangle -F

# Set default policies
iptables -P FORWARD DROP
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT

# Configure NAT (MASQUERADE)
# Translate source IP from LAN subnet to WAN IP when forwarding to WAN
iptables -t nat -A POSTROUTING -s "$LAN_SUBNET" -o "$WAN_IF" -j MASQUERADE

# Allow established and related connections
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow forwarding from LAN to WAN
iptables -A FORWARD -s "$LAN_SUBNET" -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT

# Allow forwarding from WAN to LAN (for returning packets)
iptables -A FORWARD -d "$LAN_SUBNET" -i "$WAN_IF" -o "$LAN_IF" -j ACCEPT

echo "  ✓ NAT rules configured"
echo ""

# Apply network delay using tc (traffic control) if specified
if [ "$DELAY_MS" -gt 0 ]; then
    echo "Applying network delay (${DELAY_MS}ms)..."

    # Apply delay to both interfaces
    for iface in "$WAN_IF" "$LAN_IF"; do
        # Delete existing qdisc if present
        tc qdisc del dev "$iface" root 2>/dev/null || true

        # Add delay using netem
        tc qdisc add dev "$iface" root netem delay "${DELAY_MS}ms"
        echo "  ✓ Applied ${DELAY_MS}ms delay to $iface"
    done
    echo ""
fi

# Display configuration summary
echo "========================================"
echo "NAT Router Ready"
echo "========================================"
echo "Routing: $LAN_SUBNET → $WAN_IP → $WAN_SUBNET"
echo ""
echo "iptables NAT rules:"
iptables -t nat -L -n -v
echo ""
echo "iptables FORWARD rules:"
iptables -L FORWARD -n -v
echo ""

# Keep container running
echo "NAT router is running. Press Ctrl+C to stop."
tail -f /dev/null
