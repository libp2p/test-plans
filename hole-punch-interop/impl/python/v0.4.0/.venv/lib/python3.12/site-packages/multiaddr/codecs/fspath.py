import logging
import urllib.parse
from typing import Any

from ..exceptions import BinaryParseError
from . import LENGTH_PREFIXED_VAR_SIZE, CodecBase

logger = logging.getLogger(__name__)

SIZE = LENGTH_PREFIXED_VAR_SIZE
IS_PATH = True


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """Convert a filesystem path to its binary representation."""
        logger.debug(f"[DEBUG fspath.to_bytes] input value: {string}")
        if not string:
            raise ValueError("Path cannot be empty")

        # Normalize path separators
        string = string.replace("\\", "/")

        # Remove leading/trailing slashes but preserve path components
        string = string.strip("/")

        # Handle empty path after normalization
        if not string:
            raise ValueError("Path cannot be empty after normalization")

        # URL decode to handle special characters
        string = urllib.parse.unquote(string)

        # Encode as UTF-8
        encoded = string.encode("utf-8")
        logger.debug(f"[DEBUG fspath.to_bytes] encoded bytes: {encoded!r}")
        return encoded

    def to_string(self, proto: Any, buf: bytes) -> str:
        """Convert a binary filesystem path to its string representation."""
        logger.debug(f"[DEBUG fspath.to_string] input bytes: {buf!r}")
        if not buf:
            raise ValueError("Path buffer cannot be empty")

        try:
            # Decode from UTF-8
            value = buf.decode("utf-8")
            logger.debug(f"[DEBUG fspath.to_string] decoded value: {value}")

            # Normalize path separators
            value = value.replace("\\", "/")

            # Remove leading/trailing slashes but preserve path components
            value = value.strip("/")

            # Handle empty path after normalization
            if not value:
                raise ValueError("Path cannot be empty after normalization")

            # URL encode special characters
            result = urllib.parse.quote(value)
            logger.debug(f"[DEBUG fspath.to_string] output string: {result}")

            # Add leading slash for Unix socket paths
            if proto.name == "unix":
                result = "/" + result

            return result
        except UnicodeDecodeError as e:
            raise BinaryParseError(f"Invalid UTF-8 encoding: {e!s}", buf, proto.name, e)
