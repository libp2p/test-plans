"""
DNS resolver implementation for multiaddr.

This module provides DNS resolution for multiaddrs, supporting the following protocols:
- /dns, /dns4, /dns6: Standard DNS resolution for IPv4 and IPv6
- /dnsaddr: Recursive TXT record resolution for libp2p bootstrap nodes

Features:
- Recursive resolution for /dnsaddr, /dns4, and /dns6
- Peer ID preservation during resolution
- Timeout and cancellation support (Trio)
- Error handling for recursion limits and DNS failures

Example usage:
    from multiaddr import Multiaddr
    ma = Multiaddr("/dns4/example.com/tcp/443")
    resolved = await ma.resolve()
    print(resolved)
    # [Multiaddr("/ip4/93.184.216.34/tcp/443")]
"""

import logging
import re
from typing import Any, cast

import dns.asyncresolver
import dns.rdataclass
import dns.rdtypes.ANY.TXT  # type: ignore
import dns.rdtypes.IN.A
import dns.rdtypes.IN.AAAA
import dns.resolver
import trio

from ..exceptions import RecursionLimitError, ResolutionError
from ..multiaddr import Multiaddr
from ..protocols import P_DNS, P_DNS4, P_DNS6, P_DNSADDR, Protocol
from .base import Resolver


class DNSResolver(Resolver):
    """
    DNS resolver for multiaddr.

    Resolves /dns, /dns4, /dns6, and /dnsaddr multiaddrs to their underlying IP addresses.
    Supports recursive resolution for DNSADDR records and protocol-specific resolution for
    DNS4/DNS6.
    """

    MAX_RECURSIVE_DEPTH = 32
    DEFAULT_TIMEOUT = 5.0  # 5 seconds timeout

    def __init__(self) -> None:
        """Initialize the DNS resolver."""
        self._resolver = dns.asyncresolver.Resolver()

    async def resolve(
        self, maddr: "Multiaddr", options: dict[str, Any] | None = None
    ) -> list["Multiaddr"]:
        """
        Resolve a DNS multiaddr to its actual addresses.

        Args:
            maddr: The multiaddr to resolve
            options: Optional configuration options (e.g., max_recursive_depth, signal)

        Returns:
            A list of resolved multiaddrs

        Raises:
            ResolutionError: If resolution fails
            RecursionLimitError: If maximum recursive depth is reached
            trio.Cancelled: If the operation is cancelled
        """
        protocols: list[Protocol] = list(maddr.protocols())
        if not protocols:
            raise ResolutionError("empty multiaddr")

        first_protocol = protocols[0]
        if first_protocol.code not in (P_DNS, P_DNS4, P_DNS6, P_DNSADDR):
            return [maddr]

        # Get the hostname and clean it of quotes
        hostname = maddr.value_for_protocol(first_protocol.code)
        if not hostname:
            return [maddr]

        # Remove quotes from hostname
        hostname = self._clean_quotes(hostname)

        # Get max recursive depth from options or use default
        max_depth = (
            options.get("max_recursive_depth", self.MAX_RECURSIVE_DEPTH)
            if options
            else self.MAX_RECURSIVE_DEPTH
        )

        # Get signal from options if provided
        signal = options.get("signal") if options else None

        try:
            if first_protocol.code == P_DNSADDR:
                resolved = await self._resolve_dnsaddr(
                    hostname,
                    maddr,
                    max_depth,
                    signal,
                )
                return resolved  # Do not fallback to [maddr]
            else:
                resolved = await self._resolve_dns_with_stack(maddr, signal)
                return resolved if resolved else [maddr]  # Classic DNS fallback remains
        except RecursionLimitError:
            # Do not wrap RecursionLimitError so tests can catch it
            raise
        except Exception as e:
            raise ResolutionError(f"Failed to resolve {hostname}: {e!s}")

    def _clean_quotes(self, text: str) -> str:
        """Remove quotes from a string.

        Args:
            text: The text to clean

        Returns:
            The cleaned text without quotes
        """
        # Remove all types of quotes (single, double, mixed)
        return re.sub(r'[\'"\s]+', "", text)

    async def _resolve_dnsaddr(
        self,
        hostname: str,
        original_ma: "Multiaddr",
        max_depth: int,
        signal: trio.CancelScope | None = None,
    ) -> list["Multiaddr"]:
        """
        Resolve a DNSADDR record according to libp2p specification.

        Queries TXT records from _dnsaddr.<hostname> and parses dnsaddr=<multiaddr> entries.
        Recursively resolves /dns4 and /dns6 entries to /ip4 and /ip6 addresses.

        Args:
            hostname: The hostname to resolve
            original_ma: The original multiaddr being resolved
            max_depth: Maximum depth for recursive resolution
            signal: Optional signal for cancellation

        Returns:
            A list of resolved multiaddrs

        Raises:
            ResolutionError: If resolution fails
            RecursionLimitError: If maximum recursive depth is reached
            trio.Cancelled: If the operation is cancelled
        """
        if max_depth <= 0:
            raise RecursionLimitError(f"Maximum recursive depth exceeded for {hostname}")

        # Get the peer ID if present
        peer_id = None
        try:
            peer_id = original_ma.get_peer_id()
        except Exception:
            # If there's no peer ID, that's fine - we'll just resolve the address
            pass

        # Query TXT records from _dnsaddr.<hostname> according to libp2p spec
        dnsaddr_hostname = f"_dnsaddr.{hostname}"

        try:
            if signal:
                # Use the provided signal for cancellation
                with signal:
                    return await self._query_dnsaddr_txt_records(
                        dnsaddr_hostname, peer_id, max_depth, signal
                    )
            else:
                # Use default timeout-based cancellation
                with trio.CancelScope() as cancel_scope:  # type: ignore[call-arg]
                    # Set a timeout for DNS resolution
                    cancel_scope.deadline = trio.current_time() + self.DEFAULT_TIMEOUT
                    cancel_scope.cancelled_caught = True  # type: ignore[misc]

                    return await self._query_dnsaddr_txt_records(
                        dnsaddr_hostname, peer_id, max_depth, cancel_scope
                    )
        except Exception as e:
            raise ResolutionError(f"Failed to resolve DNSADDR {hostname}: {e!s}")

    async def _query_dnsaddr_txt_records(
        self,
        dnsaddr_hostname: str,
        peer_id: str | None,
        max_depth: int,
        signal: trio.CancelScope | None = None,
        _debug_level: int = 0,
    ) -> list["Multiaddr"]:
        """
        Query TXT records and parse dnsaddr=<multiaddr> entries.

        Args:
            dnsaddr_hostname: The _dnsaddr.<hostname> to query
            peer_id: Optional peer ID to filter results
            max_depth: Maximum depth for recursive resolution
            signal: Optional signal for cancellation
            _debug_level: Internal, for debug output indentation

        Returns:
            A list of resolved multiaddrs
        """
        results = []
        indent = "  " * _debug_level
        try:
            answer = await self._resolver.resolve(dnsaddr_hostname, "TXT")
            logging.debug(
                f"{indent}Queried TXT for {dnsaddr_hostname}, "
                f"found {len(answer)} records (depth {max_depth})"
            )
            for rdata in answer:
                # Cast to TXT record type for proper attribute access
                txt_rdata = cast(dns.rdtypes.ANY.TXT.TXT, rdata)
                txt_data_raw = txt_rdata.strings[0] if txt_rdata.strings else ""
                if isinstance(txt_data_raw, bytes):
                    txt_data = txt_data_raw.decode("utf-8")
                else:
                    txt_data = str(txt_data_raw)
                logging.debug(f"{indent}  TXT: {txt_data}")
                if txt_data.startswith("dnsaddr="):
                    multiaddr_str = txt_data[8:]
                    multiaddr_str = self._clean_quotes(multiaddr_str).strip()
                    logging.debug(f"{indent}    Parsed multiaddr: {multiaddr_str}")
                    if not multiaddr_str:
                        continue
                    try:
                        parsed_ma = Multiaddr(multiaddr_str)
                        try:
                            parsed_peer_id = parsed_ma.get_peer_id()
                            logging.debug(f"{indent}      Peer ID: {parsed_peer_id}")
                        except Exception:
                            logging.debug(f"{indent}      No peer ID")
                        if peer_id:
                            try:
                                parsed_peer_id = parsed_ma.get_peer_id()
                                if parsed_peer_id != peer_id:
                                    logging.debug(f"{indent}      Skipping (peer ID mismatch)")
                                    continue
                            except Exception:
                                logging.debug(f"{indent}      Skipping (no peer ID in multiaddr)")
                                continue
                        if (
                            multiaddr_str.startswith("/dnsaddr")
                            or multiaddr_str.startswith("/dns4")
                            or multiaddr_str.startswith("/dns6")
                        ):
                            try:
                                logging.debug(f"{indent}      Recursing into {multiaddr_str}")
                                recursive_options = {"max_recursive_depth": max_depth - 1}
                                resolved = await self.resolve(parsed_ma, recursive_options)
                                for r in resolved:
                                    # Only append if not a dnsaddr/dns4/dns6 (i.e., only final IPs)
                                    if not any(
                                        p.name in ("dnsaddr", "dns4", "dns6") for p in r.protocols()
                                    ):
                                        logging.debug(f"{indent}        Final resolved: {r}")
                                        results.append(r)
                            except RecursionLimitError:
                                logging.debug(f"{indent}      Recursion limit hit!")
                                continue
                        else:
                            logging.debug(f"{indent}      Final resolved: {parsed_ma}")
                            results.append(parsed_ma)
                    except Exception as e:
                        logging.debug(f"{indent}      Error parsing multiaddr: {e}")
                        continue
        except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
            logging.debug(f"{indent}No TXT records found for {dnsaddr_hostname}")
            pass
        except Exception as e:
            logging.debug(f"{indent}Error querying TXT records for {dnsaddr_hostname}: {e}")
            raise ResolutionError(f"Failed to query TXT records for {dnsaddr_hostname}: {e!s}")
        return results

    async def _resolve_dns(
        self, hostname: str, protocol_code: int, signal: trio.CancelScope | None = None
    ) -> list["Multiaddr"]:
        """Resolve a DNS record.

        Args:
            hostname: The hostname to resolve
            protocol_code: The protocol code (DNS, DNS4, or DNS6)
            signal: Optional signal for cancellation

        Returns:
            A list of resolved multiaddrs

        Raises:
            ResolutionError: If resolution fails
            trio.Cancelled: If the operation is cancelled
        """
        try:
            if signal:
                # Use the provided signal for cancellation
                with signal:
                    results = []
                    if protocol_code in (P_DNS, P_DNS4):
                        try:
                            answer = await self._resolver.resolve(hostname, "A")
                            for rdata in answer:
                                address = str(cast(dns.rdtypes.IN.A.A, rdata).address)
                                results.append(Multiaddr(f"/ip4/{address}"))
                        except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
                            pass
                    if protocol_code in (P_DNS, P_DNS6):
                        try:
                            answer = await self._resolver.resolve(hostname, "AAAA")
                            for rdata in answer:
                                address = str(cast(dns.rdtypes.IN.AAAA.AAAA, rdata).address)
                                results.append(Multiaddr(f"/ip6/{address}"))
                        except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
                            pass
                    return results
            else:
                # No signal provided, proceed without cancellation
                results = []
                if protocol_code in (P_DNS, P_DNS4):
                    try:
                        answer = await self._resolver.resolve(hostname, "A")
                        for rdata in answer:
                            address = str(cast(dns.rdtypes.IN.A.A, rdata).address)
                            results.append(Multiaddr(f"/ip4/{address}"))
                    except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
                        pass
                if protocol_code in (P_DNS, P_DNS6):
                    try:
                        answer = await self._resolver.resolve(hostname, "AAAA")
                        for rdata in answer:
                            address = str(cast(dns.rdtypes.IN.AAAA.AAAA, rdata).address)
                            results.append(Multiaddr(f"/ip6/{address}"))
                    except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
                        pass
                return results
        except Exception as e:
            raise ResolutionError(f"Failed to resolve DNS {hostname}: {e!s}")

    async def _resolve_dns_with_stack(
        self, maddr: "Multiaddr", signal: trio.CancelScope | None = None
    ) -> list["Multiaddr"]:
        """Resolve a DNS record while preserving the rest of the multiaddr stack.

        This method handles cases like /dns4/host/tcp/port by resolving the DNS part
        and keeping the rest of the multiaddr intact.

        Args:
            maddr: The multiaddr to resolve
            signal: Optional signal for cancellation

        Returns:
            A list of resolved multiaddrs with preserved stack

        Raises:
            ResolutionError: If resolution fails
            trio.Cancelled: If the operation is cancelled
        """
        protocols = list(maddr.protocols())
        if not protocols:
            return [maddr]

        first_protocol = protocols[0]
        if first_protocol.code not in (P_DNS, P_DNS4, P_DNS6):
            return [maddr]

        # Get the hostname
        hostname = maddr.value_for_protocol(first_protocol.code)
        if not hostname:
            return [maddr]

        # Remove quotes from hostname
        hostname = self._clean_quotes(hostname)

        # Get the resolved IP addresses
        resolved_ips = await self._resolve_dns(hostname, first_protocol.code, signal)
        if not resolved_ips:
            return [maddr]

        # Split the multiaddr to get the remaining stack (everything after the DNS part)
        parts = maddr.split(1)  # Split after the first protocol
        if len(parts) < 2:
            # No remaining stack, just return the resolved IPs
            return resolved_ips

        remaining_stack = parts[1]  # Everything after the DNS part

        results = []
        for ip_maddr in resolved_ips:
            # Combine the resolved IP with the remaining stack
            if remaining_stack.protocols():
                # There's a remaining stack, encapsulate it
                combined = ip_maddr.encapsulate(remaining_stack)
            else:
                # No remaining stack, just use the IP
                combined = ip_maddr
            results.append(combined)

        return results


__all__ = ["DNSResolver"]
