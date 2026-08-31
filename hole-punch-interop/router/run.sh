#!/bin/sh

set -ex

if [ -z "$DELAY_MS" ]; then
  echo "Error: DELAY_MS is not set!"
  exit 1
fi

if [ -z "$INTERNET_SUBNET" ]; then
  echo "Error: INTERNET_SUBNET is not set!"
  exit 1
fi

# Docker does not attach the two networks to eth0 and eth1 in a fixed order, so
# the internet-facing interface is found by the subnet it carries rather than by
# name. The other interface is the LAN side.
EXTERNAL_IF=$(ip -o route show | awk -v net="$INTERNET_SUBNET" '$1 == net && $2 == "dev" { print $3; exit }')
if [ -z "$EXTERNAL_IF" ]; then
  echo "Error: no interface carries the internet subnet $INTERNET_SUBNET!"
  exit 1
fi
INTERNAL_IF=$(ls /sys/class/net | grep '^eth' | grep -v "^${EXTERNAL_IF}$" | head -n1)

ADDR_EXTERNAL=$(ip -json addr show "$EXTERNAL_IF" | jq '.[0].addr_info[0].local' -r)
SUBNET_INTERNAL=$(ip -json addr show "$INTERNAL_IF" | jq '.[0].addr_info[0].local + "/" + (.[0].addr_info[0].prefixlen | tostring)' -r)

# Set up NAT
nft add table ip nat
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
nft add rule ip nat postrouting ip saddr $SUBNET_INTERNAL oifname "$EXTERNAL_IF" snat $ADDR_EXTERNAL

# tc can only apply delays on egress traffic. By setting a delay for both interfaces, we achieve the active delay passed in as a parameter.
half_of_delay=$(expr "$DELAY_MS" / 2 )
param="${half_of_delay}ms"

tc qdisc add dev "$EXTERNAL_IF" root netem delay $param
tc qdisc add dev "$INTERNAL_IF" root netem delay $param

echo "1" > /tmp/setup_done # This will be checked by our docker HEALTHCHECK

tail -f /dev/null # Keep it running forever.
