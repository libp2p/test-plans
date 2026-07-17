#!/bin/sh

set -ex

[ -n "$DELAY_MS" ] || { echo "Error: DELAY_MS is not set!"; exit 1; }

# Docker does not guarantee eth0==internet / eth1==lan; the interface-to-network
# mapping can be assigned in either order. Derive the external interface as the one
# that routes toward the relay (which sits on the internet network) rather than
# assuming eth0. The relay name may not resolve yet at startup, so retry briefly.
relay_ip=""
i=0
while [ "$i" -lt 50 ]; do
  relay_ip=$(getent hosts relay | head -n1 | cut -d' ' -f1)
  [ -n "$relay_ip" ] && break
  i=$((i + 1))
  sleep 0.2
done
[ -n "$relay_ip" ] || { echo "Error: could not resolve relay"; exit 1; }

IFACE_EXTERNAL=$(ip -json route get "$relay_ip" | jq -r '.[0].dev')
IFACE_INTERNAL=$(ip -json addr show | jq -r --arg ext "$IFACE_EXTERNAL" \
  '.[] | select(.ifname != "lo" and .ifname != $ext and any(.addr_info[]?; .family=="inet")) | .ifname' \
  | head -n1)

ADDR_EXTERNAL=$(ip -json addr show "$IFACE_EXTERNAL" \
  | jq -r '.[0].addr_info[] | select(.family=="inet") | .local' | head -n1)
SUBNET_INTERNAL=$(ip -json addr show "$IFACE_INTERNAL" \
  | jq -r '.[0].addr_info[] | select(.family=="inet") | .local + "/" + (.prefixlen|tostring)' | head -n1)

# Set up NAT
nft add table ip nat
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
nft add rule ip nat postrouting ip saddr $SUBNET_INTERNAL oifname "$IFACE_EXTERNAL" snat $ADDR_EXTERNAL

# tc can only apply delays on egress traffic. By setting a delay on both interfaces,
# we achieve the active delay passed in as a parameter.
half_of_delay=$(expr "$DELAY_MS" / 2)
param="${half_of_delay}ms"
tc qdisc add dev "$IFACE_EXTERNAL" root netem delay $param
tc qdisc add dev "$IFACE_INTERNAL" root netem delay $param

echo "1" > /tmp/setup_done   # checked by the Docker HEALTHCHECK
tail -f /dev/null             # keep running
