import urllib.parse
from typing import Any

from ..exceptions import BinaryParseError
from . import CodecBase


class Codec(CodecBase):
    SIZE = 0  # Variable size
    IS_PATH = False  # Default to False, will be set to True for ip6zone protocol

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """Convert a UTF-8 string to its binary representation."""
        if not string:
            raise ValueError("String cannot be empty")

        # For ip6zone, ensure no leading/trailing whitespace and don't URL encode
        if proto.name == "ip6zone":
            string = string.strip()
            if not string:
                raise ValueError("Zone identifier cannot be empty after stripping whitespace")
        else:
            # URL decode the string to handle special characters for other protocols
            string = urllib.parse.unquote(string)

        # Encode as UTF-8
        encoded = string.encode("utf-8")

        # Do not add varint length prefix here; the framework handles it
        return encoded

    def to_string(self, proto: Any, buf: bytes) -> str:
        """Convert a binary UTF-8 string to its string representation."""
        if not buf:
            raise ValueError("Buffer cannot be empty")

        # Decode from UTF-8
        try:
            value = buf.decode("utf-8")
            # For ip6zone, ensure no leading/trailing whitespace and don't URL encode
            if proto.name == "ip6zone":
                value = value.strip()
                if not value:
                    raise ValueError("Zone identifier cannot be empty after stripping whitespace")
                return value
            # For other protocols, URL encode special characters
            return urllib.parse.quote(value, safe="%")
        except UnicodeDecodeError as e:
            raise BinaryParseError(f"Invalid UTF-8 encoding: {e!s}", buf, proto.name, e)
