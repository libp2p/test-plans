import socket
from typing import Any

import psutil

from .multiaddr import Multiaddr


def is_wildcard(ip: str) -> bool:
    """Check if an IP address is a wildcard address."""
    return ip in ["0.0.0.0", "::"]


def get_network_addrs(family: int) -> list[str]:
    """Get all network addresses for a given IP family (4 for IPv4, 6 for IPv6)."""
    addresses = []
    for iface, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if family == 4 and addr.family == socket.AF_INET:
                if addr.address != "127.0.0.1" and not is_link_local_ip(addr.address):
                    addresses.append(addr.address)
            elif family == 6 and addr.family == socket.AF_INET6:
                if not addr.address.startswith("::1") and not is_link_local_ip(addr.address):
                    # Remove the %scope_id if present
                    addresses.append(addr.address.split("%")[0])
    return addresses


def is_link_local_ip(ip: str) -> bool:
    """Check if an IP address is link-local."""
    if ":" in ip:  # IPv6
        return ip.startswith("fe80:")
    else:  # IPv4
        parts = ip.split(".")
        return len(parts) == 4 and parts[0] == "169" and parts[1] == "254"


def get_multiaddr_options(ma: Multiaddr) -> dict[str, Any] | None:
    """Extract options from a multiaddr (similar to toOptions() in JS).

    Returns a dictionary with 'family', 'host', 'transport', and 'port' keys,
    or None if the multiaddr doesn't represent a thin waist address.
    """
    if ma is None:
        return None

    # Parse the multiaddr to extract IP and transport information
    parts = str(ma).strip("/").split("/")

    if len(parts) < 4:
        return None

    # Look for IP protocol (ip4 or ip6)
    ip_proto = None
    ip_addr = None
    transport_proto = None
    port = None

    for i, part in enumerate(parts):
        if part in ["ip4", "ip6"]:
            if i + 1 < len(parts):
                ip_proto = part
                ip_addr = parts[i + 1]
        elif part in ["tcp", "udp"]:
            if i + 1 < len(parts):
                transport_proto = part
                try:
                    port = int(parts[i + 1])
                except (ValueError, IndexError):
                    return None

    if not all([ip_proto, ip_addr, transport_proto, port]):
        return None

    family = 4 if ip_proto == "ip4" else 6

    return {"family": family, "host": ip_addr, "transport": transport_proto, "port": port}


def get_thin_waist_addresses(
    ma: Multiaddr | None = None, port: int | None = None
) -> list[Multiaddr]:
    """Get all thin waist addresses on the current host that match the family of the
    passed multiaddr and optionally override the port.

    Wildcard IP4/6 addresses will be expanded into all available interfaces.

    Args:
        ma: The multiaddr to process. If None, returns empty list.
        port: Optional port to override the port in the multiaddr.

    Returns:
        List of Multiaddr objects representing thin waist addresses.
    """
    if ma is None:
        return []

    options = get_multiaddr_options(ma)
    if options is None:
        return []

    # Use provided port or fall back to the one in the multiaddr
    target_port = port if port is not None else options["port"]

    ip_proto = "ip4" if options["family"] == 4 else "ip6"

    if is_wildcard(options["host"]):
        # Expand wildcard addresses to all available interfaces
        addrs = []
        for host in get_network_addrs(options["family"]):
            if not is_link_local_ip(host):
                # Correct multiaddr format: /ip4/host/tcp/port or /ip6/host/tcp/port
                addr_str = f"/{ip_proto}/{host}/{options['transport']}/{target_port}"
                addrs.append(Multiaddr(addr_str))
        return addrs
    else:
        # Return the specific address
        addr_str = f"/{ip_proto}/{options['host']}/{options['transport']}/{target_port}"
        return [Multiaddr(addr_str)]
