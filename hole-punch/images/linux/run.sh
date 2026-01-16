#!/bin/bash
# Linux NAT Router Configuration Script
# Configures iptables-based NAT between LAN and WAN networks

set -euo pipefail

echo "========================================"
echo "Linux NAT Router Configuration"
echo "========================================"

# Required environment variables
WAN_IP="${WAN_IP:-}"
WAN_SUBNET="${WAN_SUBNET:-}"
LAN_IP="${LAN_IP:-}"
LAN_SUBNET="${LAN_SUBNET:-}"

# Validate required variables
if [ -z "$WAN_IP" ] || [ -z "$WAN_SUBNET" ] || [ -z "$LAN_IP" ] || [ -z "$LAN_SUBNET" ]; then
    echo "ERROR: Missing required environment variables"
    echo "Required: WAN_IP, WAN_SUBNET, LAN_IP, LAN_SUBNET"
    exit 1
fi

# Define interfaces
WAN_IF="wan0"
LAN_IF="lan0"

echo "Configuration:"
echo "  WAN Interface: $WAN_IF"
echo "  WAN IP:        $WAN_IP"
echo "  WAN Subnet:    $WAN_SUBNET"
echo "  LAN Interface: $LAN_IF"
echo "  LAN IP:        $LAN_IP"
echo "  LAN Subnet:    $LAN_SUBNET"
echo ""

# Note: Kernel parameters (ip_forward, rp_filter) are configured via
# sysctls in docker-compose.yaml for proper container operation

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

# Display configuration summary
echo "========================================"
echo "NAT Router Ready"
echo "========================================"
echo "Routing: $LAN_SUBNET ($LAN_IF) ↔ NAT ↔ $WAN_SUBNET ($WAN_IF)"
echo ""
echo "iptables NAT rules:"
iptables -t nat -L -n -v
echo ""
echo "iptables FORWARD rules:"
iptables -L FORWARD -n -v
echo ""
echo "Routing table:"
ip route show
echo ""

# Keep container running
echo "NAT router is running. Press Ctrl+C to stop."
tail -f /dev/null
