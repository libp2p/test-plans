from typing import Any

import idna

from ..exceptions import BinaryParseError
from . import LENGTH_PREFIXED_VAR_SIZE, CodecBase

SIZE = LENGTH_PREFIXED_VAR_SIZE  # Variable size for length-prefixed values
IS_PATH = False


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """Convert a domain name string to its binary representation (UTF-8),
        validating with IDNA."""
        if not string:
            raise ValueError("Domain name cannot be empty")
        try:
            # Validate using IDNA, but store as UTF-8
            idna.encode(string, uts46=True)
            return string.encode("utf-8")
        except idna.IDNAError as e:
            raise ValueError(f"Invalid domain name: {e!s}")

    def to_string(self, proto: Any, buf: bytes) -> str:
        """Convert a binary domain name to its string representation (UTF-8),
        validating with IDNA."""
        if not buf:
            raise ValueError("Domain name buffer cannot be empty")
        try:
            value = buf.decode("utf-8")
            # Validate using IDNA
            idna.encode(value, uts46=True)
            return value
        except (UnicodeDecodeError, idna.IDNAError) as e:
            raise BinaryParseError(f"Invalid domain name encoding: {e!s}", buf, proto.name, e)


def to_bytes(proto: Any, string: str) -> bytes:
    # Validate using IDNA, but store as UTF-8
    idna.encode(string, uts46=True)
    return string.encode("utf-8")


def to_string(proto: Any, buf: bytes) -> str:
    string = buf.decode("utf-8")
    # Validate using IDNA
    idna.encode(string, uts46=True)
    return string
