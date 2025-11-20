from typing import Any

from ..codecs import CodecBase
from ..exceptions import BinaryParseError, StringParseError

IS_PATH = False
SIZE = 8


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = False

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """
        Convert an IPCIDR string (eg. "24") into a single byte buffer
        """

        try:
            ip_mask = int(string)
        except ValueError:
            raise StringParseError("Invalid IPCIDR value: ", string)

        if not (0 <= ip_mask <= 255):
            raise StringParseError("IPCIDR out of range: ", string)

        return bytes([ip_mask])

    def to_string(self, proto: Any, buf: bytes) -> str:
        """
        Convert a single-byte IPCIDR buffer into a string (eg, b'\\x18' -> "24")
        """
        try:
            self.validate(buf)
            return str(buf[0])
        except Exception as e:
            raise BinaryParseError("Failed to convert IPCIDR bytes to string", buf, "ipcidr") from e

    def validate(self, b: bytes) -> None:
        """
        Validate IPCIDR buffer is exactly one byte.
        """
        if len(b) != 1:
            raise ValueError("Invalid IPCIDR length (should be == 1)")
