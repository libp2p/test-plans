import collections.abc
from collections.abc import Iterator, Sequence
from typing import Any, TypeVar, Union, overload

import varint

from . import exceptions, protocols
from .codecs import codec_by_name
from .protocols import protocol_with_name
from .transforms import bytes_iter, bytes_to_string

__all__ = ("Multiaddr",)


T = TypeVar("T")


class MultiAddrKeys(collections.abc.KeysView[Any], collections.abc.Sequence[Any]):
    def __init__(self, mapping: "Multiaddr") -> None:
        self._mapping = mapping
        super().__init__(mapping)

    def __contains__(self, value: object) -> bool:  # type: ignore[bad-param-name-override]
        proto = self._mapping.registry.find(value)
        return collections.abc.Sequence.__contains__(self, proto)

    def __getitem__(self, index: int | slice) -> Any | Sequence[Any]:
        if isinstance(index, slice):
            return list(self)[index]
        if index < 0:
            index = len(self) + index
        for idx2, proto in enumerate(self):
            if idx2 == index:
                return proto
        raise IndexError("Protocol list index out of range")

    def __hash__(self) -> int:
        return hash(tuple(self))

    def __iter__(self) -> Iterator[Any]:
        for _, proto, _, _ in bytes_iter(self._mapping.to_bytes()):
            yield proto


class MultiAddrItems(
    collections.abc.ItemsView[Any, Any], collections.abc.Sequence[tuple[Any, Any]]
):
    def __init__(self, mapping: "Multiaddr") -> None:
        self._mapping = mapping
        super().__init__(mapping)

    def __contains__(self, value: object) -> bool:  # type: ignore[bad-param-name-override]
        if not isinstance(value, tuple) or len(value) != 2:
            return False
        proto, val = value
        proto = self._mapping.registry.find(proto)
        return collections.abc.Sequence.__contains__(self, (proto, val))

    @overload
    def __getitem__(self, index: int) -> tuple[Any, Any]: ...

    @overload
    def __getitem__(self, index: slice) -> Sequence[tuple[Any, Any]]: ...

    def __getitem__(self, index: int | slice) -> tuple[Any, Any] | Sequence[tuple[Any, Any]]:
        if isinstance(index, slice):
            return list(self)[index]
        if index < 0:
            index = len(self) + index
        for idx2, item in enumerate(self):
            if idx2 == index:
                return item
        raise IndexError("Protocol item list index out of range")

    def __iter__(self) -> Iterator[tuple[Any, Any]]:
        for _, proto, codec, part in bytes_iter(self._mapping.to_bytes()):
            if codec.SIZE != 0:
                try:
                    # If we have an address, return it
                    yield proto, codec.to_string(proto, part)
                except Exception as exc:
                    raise exceptions.BinaryParseError(
                        str(exc),
                        self._mapping.to_bytes(),
                        proto.name,
                        exc,
                    ) from exc
            else:
                # We were given something like '/utp', which doesn't have
                # an address, so return None
                yield proto, None


class MultiAddrValues(collections.abc.ValuesView[Any], collections.abc.Sequence[Any]):
    def __init__(self, mapping: "Multiaddr") -> None:
        self._mapping = mapping
        super().__init__(mapping)

    def __contains__(self, value: object) -> bool:
        return collections.abc.Sequence.__contains__(self, value)

    def __getitem__(self, index: int | slice) -> Any | Sequence[Any]:
        if isinstance(index, slice):
            return list(self)[index]
        if index < 0:
            index = len(self) + index
        for idx2, value in enumerate(self):
            if idx2 == index:
                return value
        raise IndexError("Protocol value list index out of range")

    def __iter__(self) -> Iterator[Any]:
        for _, value in MultiAddrItems(self._mapping):
            yield value


class Multiaddr(collections.abc.Mapping[Any, Any]):
    """Multiaddr is a representation of multiple nested internet addresses.

    Multiaddr is a cross-protocol, cross-platform format for representing
    internet addresses. It emphasizes explicitness and self-description.

    Learn more here: https://multiformats.io/multiaddr/

    Multiaddrs have both a binary and string representation.

        >>> from multiaddr import Multiaddr
        >>> addr = Multiaddr("/ip4/1.2.3.4/tcp/80")

    Multiaddr objects are immutable, so `encapsulate` and `decapsulate`
    return new objects rather than modify internal state.
    """

    __slots__ = ("_bytes", "registry")

    def __init__(
        self, addr: Union[str, bytes, "Multiaddr"], *, registry: Any = protocols.REGISTRY
    ) -> None:
        """Instantiate a new Multiaddr.

        Args:
            addr : A string-encoded or a byte-encoded Multiaddr

        """
        self.registry = registry
        if isinstance(addr, str):
            self._from_string(addr)
        elif isinstance(addr, bytes):
            self._from_bytes(addr)
        elif isinstance(addr, Multiaddr):
            self._bytes = addr.to_bytes()
        else:
            raise TypeError("MultiAddr must be bytes, str or another MultiAddr instance")

    @classmethod
    def join(cls, *addrs: Union[str, bytes, "Multiaddr"]) -> "Multiaddr":
        """Concatenate the values of the given MultiAddr strings or objects,
        encapsulating each successive MultiAddr value with the previous ones."""
        return cls(b"".join(map(lambda a: cls(a).to_bytes(), addrs)))

    def __eq__(self, other: Any) -> bool:
        """Checks if two Multiaddr objects are exactly equal."""
        if not isinstance(other, Multiaddr):
            return NotImplemented
        return self._bytes == other._bytes

    def __str__(self) -> str:
        """Return the string representation of this Multiaddr.

        May raise a :class:`~multiaddr.exceptions.BinaryParseError` if the
        stored MultiAddr binary representation is invalid."""
        return bytes_to_string(self._bytes)

    def __contains__(self, proto: object) -> bool:
        return proto in MultiAddrKeys(self)

    def __iter__(self) -> Iterator[Any]:
        return iter(MultiAddrKeys(self))

    def __len__(self) -> int:
        return sum(1 for _ in bytes_iter(self.to_bytes()))

    def __repr__(self) -> str:
        return "<Multiaddr %s>" % str(self)

    def __hash__(self) -> int:
        return self._bytes.__hash__()

    def to_bytes(self) -> bytes:
        """Returns the byte array representation of this Multiaddr."""
        return self._bytes

    __bytes__ = to_bytes

    def protocols(self) -> MultiAddrKeys:
        """Returns a list of Protocols this Multiaddr includes."""
        return MultiAddrKeys(self)

    def split(self, maxsplit: int = -1) -> list["Multiaddr"]:
        """Returns the list of individual path components this MultiAddr is made
        up of."""
        final_split_offset = -1
        results = []
        for idx, (offset, proto, codec, part_value) in enumerate(bytes_iter(self._bytes)):
            # Split at most `maxplit` times
            if idx == maxsplit:
                final_split_offset = offset
                break

            # Re-assemble binary MultiAddr representation
            part_size = varint.encode(len(part_value)) if codec.SIZE < 0 else b""
            part = b"".join((proto.vcode, part_size, part_value))

            # Add MultiAddr with the given value
            results.append(self.__class__(part))
        # Add final item with remainder of MultiAddr if there is anything left
        if final_split_offset >= 0:
            results.append(self.__class__(self._bytes[final_split_offset:]))
        return results

    keys = protocols

    def items(self) -> MultiAddrItems:
        return MultiAddrItems(self)

    def values(self) -> MultiAddrValues:
        return MultiAddrValues(self)

    def encapsulate(self, other: Union[str, bytes, "Multiaddr"]) -> "Multiaddr":
        """Wrap this Multiaddr around another.

        For example:
            /ip4/1.2.3.4 encapsulate /tcp/80 = /ip4/1.2.3.4/tcp/80
        """
        return self.__class__.join(self, other)

    def decapsulate(self, addr: Union["Multiaddr", str]) -> "Multiaddr":
        """Remove a Multiaddr wrapping.

        For example:
            /ip4/1.2.3.4/tcp/80 decapsulate /ip4/1.2.3.4 = /tcp/80
        """
        addr_str = str(addr)
        s = str(self)
        i = s.rindex(addr_str)
        if i < 0:
            raise ValueError(f"Address {s} does not contain subaddress: {addr_str}")
        return Multiaddr(s[:i])

    def decapsulate_code(self, code: int) -> "Multiaddr":
        """
        Remove the last occurrence of the protocol with the given code and everything after it.
        If the protocol code is not present, return the original multiaddr.
        """
        # Find all protocol codes and their offsets
        offsets = []
        for offset, proto, codec, part_value in bytes_iter(self._bytes):
            offsets.append((offset, proto.code))
        # Find the last occurrence of the code
        last_index = -1
        for i, (offset, proto_code) in enumerate(offsets):
            if proto_code == code:
                last_index = i
        if last_index == -1:
            # Protocol code not found, return original
            return self
        # Get the offset to slice up to
        cut_offset = offsets[last_index][0]
        if cut_offset == 0:
            return self.__class__("")
        return self.__class__(self._bytes[:cut_offset])

    def value_for_protocol(self, proto: Any) -> Any | None:
        """Return the value (if any) following the specified protocol

        Returns
        -------
        Union[object, NoneType]
            The parsed protocol value for the given protocol code or ``None``
            if the given protocol does not require any value

        Raises
        ------
        ~multiaddr.exceptions.BinaryParseError
            The stored MultiAddr binary representation is invalid
        ~multiaddr.exceptions.ProtocolLookupError
            MultiAddr does not contain any instance of this protocol
        """
        proto = self.registry.find(proto)
        for proto2, value in self.items():
            if proto2 is proto or proto2 == proto:
                return value
        raise exceptions.ProtocolLookupError(proto, str(self))

    def __getitem__(self, proto: Any) -> Any:
        """Returns the value for the given protocol.

        Raises
        ------
        ~multiaddr.exceptions.ProtocolLookupError
            If the protocol is not found in this Multiaddr.
        ~multiaddr.exceptions.BinaryParseError
            If the protocol value is invalid.
        """
        proto = self.registry.find(proto)
        for _, p, codec, part in bytes_iter(self._bytes):
            if p == proto:
                if codec.SIZE == 0:
                    return None
                try:
                    return codec.to_string(proto, part)
                except Exception as exc:
                    raise exceptions.BinaryParseError(
                        str(exc),
                        self._bytes,
                        proto.name,
                        exc,
                    ) from exc
        raise exceptions.ProtocolLookupError(proto, str(self))

    async def resolve(self) -> list["Multiaddr"]:
        """Resolve this multiaddr if it contains a resolvable protocol.

        Returns:
            A list of resolved multiaddrs
        """
        from .resolvers.dns import DNSResolver

        resolver: DNSResolver = DNSResolver()
        return await resolver.resolve(self)

    def _from_string(self, addr: str) -> None:
        """Parse a string multiaddr.

        Args:
            addr: The multiaddr string to parse.

        Raises:
            StringParseError: If the string multiaddr is invalid.
        """
        if not addr:
            # Allow empty multiaddrs (like JavaScript implementation)
            self._bytes = b""
            return

        # Handle other protocols
        parts = iter(addr.strip("/").split("/"))
        if not parts:
            raise exceptions.StringParseError("empty multiaddr", addr)

        self._bytes = b""
        for part in parts:
            if not part:
                continue

            # Special handling for unix paths
            if part in ("unix",):
                try:
                    # Get the next part as the path value
                    protocol_path_value = next(parts)
                    if not protocol_path_value:
                        raise exceptions.StringParseError("empty protocol path", addr)

                    # Join any remaining parts as part of the path
                    remaining_parts = []
                    while True:
                        try:
                            next_part = next(parts)
                            if not next_part:
                                continue
                            remaining_parts.append(next_part)
                        except StopIteration:
                            break

                    if remaining_parts:
                        protocol_path_value = protocol_path_value + "/" + "/".join(remaining_parts)

                    proto = protocol_with_name(part)
                    codec = codec_by_name(proto.codec)
                    if not codec:
                        raise exceptions.StringParseError(f"unknown codec: {proto.codec}", addr)

                    try:
                        self._bytes += varint.encode(proto.code)
                        buf = codec.to_bytes(proto, protocol_path_value)
                        # Add length prefix for variable-sized or zero-sized codecs
                        if codec.SIZE <= 0:
                            self._bytes += varint.encode(len(buf))
                        if buf:  # Only append buffer if it's not empty
                            self._bytes += buf
                    except Exception as e:
                        raise exceptions.StringParseError(str(e), addr) from e
                    continue
                except StopIteration:
                    raise exceptions.StringParseError("missing value for unix protocol", addr)

            # Handle other protocols
            # Split protocol name and value if present
            protocol_value: str | None = None
            if "=" in part:
                proto_name, protocol_value = part.split("=", 1)
            else:
                proto_name = part

            try:
                proto = protocol_with_name(proto_name)
            except Exception as exc:
                raise exceptions.StringParseError(f"unknown protocol: {proto_name}", addr) from exc

            # If the protocol expects a value, get it
            if proto.codec is not None:
                if protocol_value is None:
                    try:
                        protocol_value = next(parts)
                    except StopIteration:
                        raise exceptions.StringParseError(
                            f"missing value for protocol: {proto_name}", addr
                        )
                # Validate value (optional: could add more checks here)
                # If value looks like a protocol name, that's an error
                if protocol_value is not None:
                    try:
                        protocol_with_name(protocol_value)
                        # If no exception, value is a protocol name, which is not allowed here
                        raise exceptions.StringParseError(
                            f"expected value for protocol {proto_name}, "
                            f"got protocol name {protocol_value}",
                            addr,
                        )
                    except exceptions.ProtocolNotFoundError:
                        pass  # value is not a protocol name, so it's valid as a value

            codec = codec_by_name(proto.codec)
            if not codec:
                raise exceptions.StringParseError(f"unknown codec: {proto.codec}", addr)

            try:
                self._bytes += varint.encode(proto.code)

                # Special case: protocols with codec=None are flag protocols
                # (no value, no length prefix, no buffer)
                if proto.codec is None:
                    continue

                buf = codec.to_bytes(proto, protocol_value or "")
                if codec.SIZE <= 0:  # Add length prefix for variable-sized or zero-sized codecs
                    self._bytes += varint.encode(len(buf))
                if buf:  # Only append buffer if it's not empty
                    self._bytes += buf
            except Exception as e:
                raise exceptions.StringParseError(str(e), addr) from e

    def _from_bytes(self, addr: bytes) -> None:
        """Parse a binary multiaddr.

        Args:
            addr: The multiaddr bytes to parse.

        Raises:
            BinaryParseError: If the binary multiaddr is invalid.
        """
        if not addr:
            # Allow empty multiaddrs (like JavaScript implementation)
            self._bytes = b""
            return

        self._bytes = addr

    def get_peer_id(self) -> str | None:
        """Get the peer ID from the multiaddr.

        For circuit addresses, returns the target peer ID, not the relay peer ID.

        Returns:
            The peer ID if found, None otherwise.

        Raises:
            BinaryParseError: If the binary multiaddr is invalid.
        """
        try:
            tuples = []

            for _, proto, codec, part in bytes_iter(self._bytes):
                if proto.name == "p2p":
                    tuples.append((proto, part))

                # If this is a p2p-circuit address, reset tuples to get target peer id
                # not the peer id of the relay
                if proto.name == "p2p-circuit":
                    tuples = []

            # Get the last p2p tuple (target peer ID for circuits)
            if tuples:
                last_tuple = tuples[-1]
                proto, part = last_tuple
                # Get the codec for this specific protocol
                codec = codec_by_name(proto.codec)
                # Handle both fixed-size and variable-sized codecs
                if codec is not None and codec.SIZE != 0:
                    return codec.to_string(proto, part)

            return None
        except Exception:
            return None
