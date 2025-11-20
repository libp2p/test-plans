"""
Multiaddr Protocol Codes and Registry

This module defines all supported multiaddr protocol codes, their names, and their encodings.

Key features:
- Protocol code constants (e.g., P_IP4, P_TCP, P_DNSADDR)
- Protocol class for protocol metadata
- ProtocolRegistry for fast lookup and aliasing
- Reference to the multicodec table for protocol codes

Common protocol codes:
    P_IP4 = 0x04      # IPv4
    P_IP6 = 0x29      # IPv6
    P_TCP = 0x06      # TCP
    P_UDP = 0x0111    # UDP
    P_DNS = 0x35      # DNS (any)
    P_DNS4 = 0x36     # DNS (IPv4)
    P_DNS6 = 0x37     # DNS (IPv6)
    P_DNSADDR = 0x38  # DNSADDR (libp2p)
    P_P2P = 0x01A5    # Peer ID
    P_TLS = 0x01C0    # TLS
    P_HTTP = 0x01E0   # HTTP
    P_HTTPS = 0x01BB  # HTTPS
    ...

For a full list, see the PROTOCOLS list and the multicodec table:
https://github.com/multiformats/multicodec/blob/master/table.csv

Example usage:
    from multiaddr.protocols import P_TCP, protocol_with_code
    print(P_TCP)  # 6
    proto = protocol_with_code(P_TCP)
    print(proto.name)  # 'tcp'
"""

from typing import Any

import varint

from . import exceptions
from .codecs import codec_by_name

__all__ = ("PROTOCOLS", "REGISTRY", "Protocol")


# source of protocols https://github.com/multiformats/multicodec/blob/master/table.csv#L382

P_IP4 = 0x04
P_IP6 = 0x29
P_IP6ZONE = 0x2A
P_IPCIDR = 0x2B
P_TCP = 0x06
P_UDP = 0x0111
P_DCCP = 0x21
P_SCTP = 0x84
P_UDT = 0x012D
P_UTP = 0x012E
P_P2P = 0x01A5
P_HTTP = 0x01E0
P_HTTPS = 0x01BB
P_TLS = 0x01C0
P_QUIC = 0x01CC
P_QUIC1 = 0x01CD
P_WS = 0x01DD
P_WSS = 0x01DE
P_ONION = 0x01BC
P_ONION3 = 0x01BD
P_GARLIC64 = 0x1BE
P_GARLIC32 = 0x1BF
P_P2P_CIRCUIT = 0x0122
P_DNS = 0x35
P_DNS4 = 0x36
P_DNS6 = 0x37
P_DNSADDR = 0x38
P_P2P_WEBSOCKET_STAR = 0x01DF
P_P2P_WEBRTC_STAR = 0x0113
P_P2P_WEBRTC_DIRECT = 0x0114
P_UNIX = 0x0190
P_HTTP_PATH = 0x01E1
P_SNI = 0x01C1
P_NOISE = 0x01C6
P_WEBTRANSPORT = 0x01D1
P_WEBRTC_DIRECT = 0x118
P_WEBRTC = 0x119
P_MEMORY = 0x309
P_CERTHASH = 0x1D2


class Protocol:
    __slots__ = [
        "code",  # int
        "codec",  # string
        "name",  # string
    ]

    def __init__(self, code: int, name: str, codec: str | None) -> None:
        if not isinstance(code, int):
            raise TypeError("code must be an integer")
        if not isinstance(name, str):
            raise TypeError("name must be a string")
        if not isinstance(codec, str) and codec is not None:
            raise TypeError("codec must be a string or None")

        self.code = code
        self.name = name
        self.codec = codec

    @property
    def size(self) -> int:
        return codec_by_name(self.codec).SIZE

    @property
    def path(self) -> bool:
        return codec_by_name(self.codec).IS_PATH

    @property
    def vcode(self) -> bytes:
        return varint.encode(self.code)

    def __eq__(self, other: Any) -> bool:
        if not isinstance(other, Protocol):
            return NotImplemented

        return all(
            (
                self.code == other.code,
                self.name == other.name,
                self.codec == other.codec,
                self.path == other.path,
            )
        )

    def __hash__(self) -> int:
        return hash((self.code, self.name))

    def __repr__(self) -> str:
        return "Protocol(code={code!r}, name={name!r}, codec={codec!r})".format(
            code=self.code,
            name=self.name,
            codec=self.codec,
        )


# List of multiaddr protocols supported by this module by default
PROTOCOLS = [
    Protocol(P_IP4, "ip4", "ip4"),
    Protocol(P_TCP, "tcp", "uint16be"),
    Protocol(P_UDP, "udp", "uint16be"),
    Protocol(P_DCCP, "dccp", "uint16be"),
    Protocol(P_IP6, "ip6", "ip6"),
    Protocol(P_IP6ZONE, "ip6zone", "utf8"),
    Protocol(P_IPCIDR, "ipcidr", "ipcidr"),
    Protocol(P_DNS, "dns", "domain"),
    Protocol(P_DNS4, "dns4", "domain"),
    Protocol(P_DNS6, "dns6", "domain"),
    Protocol(P_DNSADDR, "dnsaddr", "domain"),
    Protocol(P_SNI, "sni", "domain"),
    Protocol(P_NOISE, "noise", None),
    Protocol(P_SCTP, "sctp", "uint16be"),
    Protocol(P_UDT, "udt", None),
    Protocol(P_UTP, "utp", None),
    Protocol(P_P2P, "p2p", "cid"),
    Protocol(P_ONION, "onion", "onion"),
    Protocol(P_ONION3, "onion3", "onion3"),
    Protocol(P_GARLIC64, "garlic64", "garlic64"),
    Protocol(P_GARLIC32, "garlic32", "garlic32"),
    Protocol(P_QUIC, "quic", None),
    Protocol(P_QUIC1, "quic-v1", None),
    Protocol(P_HTTP, "http", None),
    Protocol(P_HTTPS, "https", None),
    Protocol(P_HTTP_PATH, "http-path", "http_path"),
    Protocol(P_TLS, "tls", None),
    Protocol(P_WS, "ws", None),
    Protocol(P_WSS, "wss", None),
    Protocol(P_P2P_WEBSOCKET_STAR, "p2p-websocket-star", None),
    Protocol(P_P2P_WEBRTC_STAR, "p2p-webrtc-star", None),
    Protocol(P_P2P_WEBRTC_DIRECT, "p2p-webrtc-direct", None),
    Protocol(P_P2P_CIRCUIT, "p2p-circuit", None),
    Protocol(P_WEBTRANSPORT, "webtransport", None),
    Protocol(P_UNIX, "unix", "fspath"),
    Protocol(P_WEBRTC_DIRECT, "webrtc-direct", None),
    Protocol(P_WEBRTC, "webrtc", None),
    Protocol(P_MEMORY, "memory", "memory"),
    Protocol(P_CERTHASH, "certhash", "certhash"),
]


class ProtocolRegistry:
    """A collection of individual Multiaddr protocols indexed for fast lookup"""

    __slots__ = ("_codes_to_protocols", "_locked", "_names_to_protocols")

    def __init__(self, protocols: list[Protocol] | tuple[Protocol, ...] = ()) -> None:
        self._locked = False
        protocols_tuple = tuple(protocols) if isinstance(protocols, list) else protocols
        self._codes_to_protocols: dict[int, Protocol] = {
            proto.code: proto for proto in protocols_tuple
        }
        self._names_to_protocols: dict[str, Protocol] = {
            proto.name: proto for proto in protocols_tuple
        }

    def add(self, proto: Protocol) -> Protocol:
        """Add the given protocol description to this registry

        Raises
        ------
        ~multiaddr.exceptions.ProtocolRegistryLocked
            Protocol registry is locked and does not accept any new entries.

            You can use `.copy(unlock=True)` to copy an existing locked registry
            and unlock it.
        ~multiaddr.exceptions.ProtocolExistsError
            A protocol with the given name or code already exists.
        """
        if self._locked:
            raise exceptions.ProtocolRegistryLocked()

        if proto.name in self._names_to_protocols:
            raise exceptions.ProtocolExistsError(proto, "name")

        if proto.code in self._codes_to_protocols:
            raise exceptions.ProtocolExistsError(proto, "code")

        self._names_to_protocols[proto.name] = proto
        self._codes_to_protocols[proto.code] = proto
        return proto

    def add_alias_name(self, proto: Protocol | str, alias_name: str) -> None:
        """Add an alternate name for an existing protocol description to the registry

        Raises
        ------
        ~multiaddr.exceptions.ProtocolRegistryLocked
            Protocol registry is locked and does not accept any new entries.

            You can use `.copy(unlock=True)` to copy an existing locked registry
            and unlock it.
        ~multiaddr.exceptions.ProtocolExistsError
            A protocol with the given name already exists.
        ~multiaddr.exceptions.ProtocolNotFoundError
            No protocol matching *proto* could be found.
        """
        if self._locked:
            raise exceptions.ProtocolRegistryLocked()

        proto = self.find(proto)
        assert self._names_to_protocols.get(proto.name) is proto, (
            "Protocol to alias must have already been added to the registry"
        )

        if alias_name in self._names_to_protocols:
            raise exceptions.ProtocolExistsError(self._names_to_protocols[alias_name], "name")

        self._names_to_protocols[alias_name] = proto

    def add_alias_code(self, proto: Protocol | int, alias_code: int) -> None:
        """Add an alternate code for an existing protocol description to the registry

        Raises
        ------
        ~multiaddr.exceptions.ProtocolRegistryLocked
            Protocol registry is locked and does not accept any new entries.

            You can use `.copy(unlock=True)` to copy an existing locked registry
            and unlock it.
        ~multiaddr.exceptions.ProtocolExistsError
            A protocol with the given code already exists.
        ~multiaddr.exceptions.ProtocolNotFoundError
            No protocol matching *proto* could be found.
        """
        if self._locked:
            raise exceptions.ProtocolRegistryLocked()

        proto = self.find(proto)
        assert self._codes_to_protocols.get(proto.code) is proto, (
            "Protocol to alias must have already been added to the registry"
        )

        if alias_code in self._codes_to_protocols:
            raise exceptions.ProtocolExistsError(self._codes_to_protocols[alias_code], "name")

        self._codes_to_protocols[alias_code] = proto

    def lock(self) -> None:
        """Lock this registry instance to deny any further changes"""
        self._locked = True

    @property
    def locked(self) -> bool:
        return self._locked

    def copy(self, *, unlock: bool = False) -> "ProtocolRegistry":
        """Create a copy of this protocol registry

        Arguments
        ---------
        unlock
            Create the copied registry unlocked even if the current one is locked?
        """
        registry = ProtocolRegistry()
        registry._locked = self._locked and not unlock
        registry._codes_to_protocols = self._codes_to_protocols.copy()
        registry._names_to_protocols = self._names_to_protocols.copy()
        return registry

    __copy__ = copy

    def find_by_name(self, name: str) -> Protocol:
        """Find a protocol by its name

        Raises
        ------
        ~multiaddr.exceptions.ProtocolNotFoundError
            No protocol matching *name* could be found.
        """
        try:
            return self._names_to_protocols[name]
        except KeyError:
            raise exceptions.ProtocolNotFoundError(name)

    def find_by_code(self, code: int) -> Protocol:
        """Find a protocol by its code

        Raises
        ------
        ~multiaddr.exceptions.ProtocolNotFoundError
            No protocol matching *code* could be found.
        """
        try:
            return self._codes_to_protocols[code]
        except KeyError:
            raise exceptions.ProtocolNotFoundError(code)

    def find(self, proto: Protocol | str | int) -> Protocol:
        """Find a protocol by its name, code, or Protocol instance

        Raises
        ------
        ~multiaddr.exceptions.ProtocolNotFoundError
            No protocol matching *proto* could be found.
        """
        if isinstance(proto, Protocol):
            return proto
        elif isinstance(proto, str):
            return self.find_by_name(proto)
        elif isinstance(proto, int):
            return self.find_by_code(proto)
        else:
            raise TypeError("Protocol must be a string, integer, or Protocol instance")


# Create a registry with all the default protocols
REGISTRY = ProtocolRegistry(PROTOCOLS)
REGISTRY.lock()


def protocol_with_name(name: str) -> Protocol:
    """Find a protocol by its name

    Raises
    ------
    ~multiaddr.exceptions.ProtocolNotFoundError
        No protocol matching *name* could be found.
    """
    return REGISTRY.find_by_name(name)


def protocol_with_code(code: int) -> Protocol:
    """Find a protocol by its code

    Raises
    ------
    ~multiaddr.exceptions.ProtocolNotFoundError
        No protocol matching *code* could be found.
    """
    return REGISTRY.find_by_code(code)


def protocol_with_any(proto: Protocol | str | int) -> Protocol:
    """Find a protocol by its name, code, or Protocol instance

    Raises
    ------
    ~multiaddr.exceptions.ProtocolNotFoundError
        No protocol matching *proto* could be found.
    """
    return REGISTRY.find(proto)


def protocols_with_string(string: str) -> list[Protocol]:
    """Find all protocols that are part of the given string

    Raises
    ------
    ~multiaddr.exceptions.StringParseError
        The given string is not a valid multiaddr string.
    ~multiaddr.exceptions.ProtocolNotFoundError
        If a protocol in the string is not found.
    """
    if not string:
        return []
    if not string.startswith("/"):
        string = "/" + string
    # consume trailing slashes
    string = string.rstrip("/")
    sp = string.split("/")

    # skip the first element, since it starts with /
    sp.pop(0)
    protocols = []
    while sp:
        element = sp.pop(0)
        if not element:  # Skip empty elements from multiple slashes
            continue
        try:
            proto = protocol_with_name(element)
            protocols.append(proto)
            if proto.codec is not None:
                codec = codec_by_name(proto.codec)
                if proto.name == "unix":
                    # For unix, consume all remaining elements as part of the path
                    if sp:
                        path_value = "/".join(sp)
                        try:
                            codec.to_bytes(proto, path_value)
                            sp.clear()
                            continue
                        except Exception as exc:
                            raise exceptions.StringParseError(
                                f"Invalid path value for protocol {proto.name}",
                                string,
                                proto.name,
                                exc,
                            ) from exc
                    else:
                        raise exceptions.StringParseError(
                            f"Protocol {proto.name} requires a path value",
                            string,
                            proto.name,
                            ValueError("Missing required path value"),
                        )
                elif sp:
                    # Find next non-empty element
                    next_elem = None
                    while sp and not next_elem:
                        next_elem = sp[0]
                        if not next_elem:  # Skip empty elements
                            sp.pop(0)
                            continue

                    if next_elem:  # Only proceed if we found a non-empty element
                        # First try to validate as value for current protocol
                        try:
                            codec.to_bytes(proto, next_elem)
                            sp.pop(0)
                            continue
                        except Exception as exc:
                            # If value validation fails, check if it's a protocol name
                            if next_elem.isalnum():
                                try:
                                    protocol_with_name(next_elem)
                                    if proto.name in ["ip6zone"]:
                                        if not any(codec.to_bytes(proto, val) for val in sp if val):
                                            raise exceptions.StringParseError(
                                                f"Protocol {proto.name} requires a value",
                                                string,
                                                proto.name,
                                                ValueError("Missing required value"),
                                            )
                                    continue
                                except exceptions.ProtocolNotFoundError:
                                    raise exceptions.StringParseError(
                                        f"Invalid value for protocol {proto.name}",
                                        string,
                                        proto.name,
                                        exc,
                                    ) from exc
                            else:
                                raise exceptions.StringParseError(
                                    f"Invalid value for protocol {proto.name}",
                                    string,
                                    proto.name,
                                    exc,
                                ) from exc
                    else:
                        if proto.name in ["ip6zone"]:
                            raise exceptions.StringParseError(
                                f"Protocol {proto.name} requires a value",
                                string,
                                proto.name,
                                ValueError("Missing required value"),
                            )
                else:
                    if proto.name in ["ip6zone"]:
                        raise exceptions.StringParseError(
                            f"Protocol {proto.name} requires a value",
                            string,
                            proto.name,
                            ValueError("Missing required value"),
                        )
        except exceptions.ProtocolNotFoundError as exc:
            raise exc

    return protocols
