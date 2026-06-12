# Router

This directory contains a Debian-based router implemented on top of nftables.

It expects to be run with two network interfaces: one "external" interface facing the
`internet` network and one "internal" interface facing the LAN.

The order of the interfaces is **not** important.
Docker does not guarantee that interface index order (`eth0`, `eth1`) matches the order
the networks are listed, so the router autodetects which interface is which at startup:
the external interface is the one that routes toward the `relay` (which lives on the
`internet` network), and the other inet-bearing interface is treated as internal.
The firewall is set up to take incoming traffic on the internal interface and forward +
masquerade it to the external one.

It also expects an env variable `DELAY_MS` to be set and will apply this delay as part of the routing process[^1].

[^1]: This is done via `tc qdisc` which only works for egress traffic. To ensure the delay applies in both directions, we divide it by 2 and apply it on both interfaces.
