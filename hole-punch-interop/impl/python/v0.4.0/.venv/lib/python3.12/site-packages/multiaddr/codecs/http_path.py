import re
from typing import Any
from urllib.parse import quote, unquote

from ..codecs import CodecBase
from ..exceptions import BinaryParseError, StringParseError

IS_PATH = False
SIZE = -1  # LengthPrefixedVarSize


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """
        Convert an HTTP path string to bytes
        Unescape URL-encoded characters, validated non-empty, then encode
        as UTF-8
        """

        # Reject invalid percent-escapes like "%zz" or "%f" (but allow standalone %)
        # Look for % followed by exactly 1 hex digit OR % followed by non-hex characters OR % at end
        invalid_escape = (
            re.search(r"%[0-9A-Fa-f](?![0-9A-Fa-f])", string)
            or re.search(r"%[^0-9A-Fa-f]", string)
            or re.search(r"%$", string)
        )
        if invalid_escape:
            raise StringParseError("Invalid percent-escape in path", string)

        # Now safely unquote
        try:
            unescaped = unquote(string)
        except Exception:
            raise StringParseError("Invalid HTTP path string", string)

        if not unescaped:
            raise StringParseError("empty http path is not allowed", string)

        return unescaped.encode("utf-8")

    def to_string(self, proto: Any, buf: bytes) -> str:
        """
        Convert bytes to an HTTP path string
        Decode as UTF-8 and URL-encode (matches Go implementation)
        """
        if len(buf) == 0:
            raise BinaryParseError("Empty http path is not allowed", buf, "http-path")

        return quote(buf.decode("utf-8"), safe="")

    def validate(self, b: bytes) -> None:
        """
        Validate an HTTP path buffer.
        Just check non-empty.
        """
        if len(b) == 0:
            raise ValueError("Empty http path is not allowed")
