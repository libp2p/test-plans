import base64
import binascii
from typing import Any

from ..codecs import CodecBase
from ..exceptions import BinaryParseError

SIZE = 296
IS_PATH = False


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        try:
            addr, port = string.split(":", 1)
            if addr.endswith(".onion"):
                addr = addr[:-6]
            if len(addr) != 56:
                raise ValueError("Invalid onion3 address length")
            if not port.isdigit():
                raise ValueError("Invalid onion3 port")
            port_num = int(port)
            if not 1 <= port_num <= 65535:
                raise ValueError("Invalid onion3 port range")
            # onion3 address is standard base32 (lowercase, no padding)
            try:
                addr_bytes = base64.b32decode(addr.upper())
            except binascii.Error:
                raise ValueError("Invalid base32 encoding")
            if len(addr_bytes) != 35:
                raise ValueError("Decoded onion3 address must be 35 bytes")
            return addr_bytes + port_num.to_bytes(2, byteorder="big")
        except (ValueError, UnicodeEncodeError, binascii.Error) as e:
            raise BinaryParseError(str(e), string.encode(), proto)

    def to_string(self, proto: Any, buf: bytes) -> str:
        try:
            if len(buf) != 37:
                raise ValueError("Invalid onion3 address length")
            try:
                addr = base64.b32encode(buf[:35]).decode("ascii").lower()
            except binascii.Error:
                raise ValueError("Invalid base32 encoding")
            # Remove padding
            addr = addr.rstrip("=")
            if len(addr) != 56:
                raise ValueError("Invalid onion3 address length")
            port = str(int.from_bytes(buf[35:], byteorder="big"))
            if not 1 <= int(port) <= 65535:
                raise ValueError("Invalid onion3 port range")
            return f"{addr}:{port}"
        except (ValueError, UnicodeDecodeError, binascii.Error) as e:
            raise BinaryParseError(str(e), buf, proto)
