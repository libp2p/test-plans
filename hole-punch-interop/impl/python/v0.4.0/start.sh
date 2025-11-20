#!/bin/sh
# Setup NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# Start Python app
exec python hole_punch.py
