from typing import Any


class Error(Exception):
    pass


class MultiaddrLookupError(LookupError, Error):
    pass


class ProtocolLookupError(MultiaddrLookupError):
    """
    MultiAddr did not contain a protocol with the requested code
    """

    def __init__(self, proto: Any, string: str) -> None:
        self.proto = proto
        self.string = string

        super().__init__(f"MultiAddr {string!r} does not contain protocol {proto}")


class ParseError(ValueError, Error):
    pass


class StringParseError(ParseError):
    """
    MultiAddr string representation could not be parsed
    """

    def __init__(
        self,
        message: str,
        string: str,
        protocol: str | None = None,
        original: Exception | None = None,
    ) -> None:
        self.message = message
        self.string = string
        self.protocol = protocol
        self.original = original

        if protocol:
            message = f"Invalid MultiAddr {string!r} protocol {protocol}: {message}"
        else:
            message = f"Invalid MultiAddr {string!r}: {message}"

        super().__init__(message)

    def __str__(self) -> str:
        base = super().__str__()
        if self.protocol is not None:
            base += f" (protocol: {self.protocol})"
        if self.string is not None:
            base += f" (string: {self.string})"
        if self.original is not None:
            base += f" (cause: {self.original})"
        return base


class BinaryParseError(ParseError):
    """
    MultiAddr binary representation could not be parsed
    """

    def __init__(
        self,
        message: str,
        binary: bytes,
        protocol: str | int,
        original: Exception | None = None,
    ) -> None:
        self.message = message
        self.binary = binary
        self.protocol = protocol
        self.original = original

        message = f"Invalid binary MultiAddr protocol {protocol}: {message}"

        super().__init__(message)

    def __str__(self) -> str:
        base = super().__str__()
        if self.protocol is not None:
            base += f" (protocol: {self.protocol})"
        if self.binary is not None:
            base += f" (binary: {self.binary!r})"
        if self.original is not None:
            base += f" (cause: {self.original})"
        return base


class ProtocolRegistryError(Error):
    pass


ProtocolManagerError = ProtocolRegistryError


class ProtocolRegistryLocked(Error):
    """Protocol registry was locked and doesn't allow any further additions"""

    def __init__(self) -> None:
        super().__init__("Protocol registry is locked and does not accept any new values")


class ProtocolExistsError(ProtocolRegistryError):
    """Protocol with the given name or code already exists"""

    def __init__(self, proto: Any, kind: str = "name") -> None:
        self.proto = proto
        self.kind = kind

        super().__init__(f"Protocol with {kind} {getattr(proto, kind)!r} already exists")


class ProtocolNotFoundError(ProtocolRegistryError):
    """No protocol with the given name or code found"""

    def __init__(self, value: str | int, kind: str = "name") -> None:
        self.value = value
        self.kind = kind

        super().__init__(f"No protocol with {kind} {value!r} found")


class MultiaddrError(Exception):
    """Base exception for multiaddr errors."""

    def __init__(self, message: str = "Multiaddr error"):
        super().__init__(message)
        self.name = "MultiaddrError"


class ResolutionError(MultiaddrError):
    """Raised when resolution fails."""

    def __init__(self, message: str = "Resolution failed"):
        super().__init__(message)
        self.name = "ResolutionError"


class RecursionLimitError(ResolutionError):
    """Raised when the maximum recursive depth is reached."""

    def __init__(self, message: str = "Max recursive depth reached"):
        super().__init__(message)
        self.name = "RecursionLimitError"
