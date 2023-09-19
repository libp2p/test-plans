#!/bin/sh

set -ex

# Wait for interfaces to be up and running ...
while ! ip addr show eth0; do sleep 1; done
while ! ip addr show eth1; do sleep 1; done

ADDR_EXTERNAL=$(ip -json addr show eth1 | jq '.[0].addr_info[0].local' -r)
SUBNET_INTERNAL=$(ip -json addr show eth0 | jq '.[0].addr_info[0].local + "/" + (.[0].addr_info[0].prefixlen | tostring)' -r)

# Set up NAT
nft add table ip nat
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
nft add rule ip nat postrouting ip saddr $SUBNET_INTERNAL oifname "eth1" snat $ADDR_EXTERNAL

# tc can only apply delays on egress traffic. By setting a delay for both eth0 and eth1, we have an effective delay of 100ms in both directions.
tc qdisc add dev eth0 root netem delay 50ms
tc qdisc add dev eth1 root netem delay 50ms

echo "1" > /var/setup_done # This will be checked by our docker HEALTHCHECK

tail -f /dev/null # Keep it running forever.
