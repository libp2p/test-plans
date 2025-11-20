import base64
import binascii
from typing import Any

from ..codecs import CodecBase
from ..exceptions import BinaryParseError

SIZE = 96
IS_PATH = False


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        try:
            addr, port = string.split(":", 1)
            if addr.endswith(".onion"):
                addr = addr[:-6]
            if len(addr) != 16:
                raise ValueError("Invalid onion address length")
            if not port.isdigit():
                raise ValueError("Invalid onion port")
            port_num = int(port)
            if not 1 <= port_num <= 65535:
                raise ValueError("Invalid onion port range")
            # onion address is standard base32 (lowercase, no padding)
            addr_bytes = base64.b32decode(addr.upper())
            if len(addr_bytes) != 10:
                raise ValueError("Decoded onion address must be 10 bytes")
            return addr_bytes + port_num.to_bytes(2, byteorder="big")
        except (ValueError, UnicodeEncodeError, binascii.Error) as e:
            raise BinaryParseError(str(e), string.encode(), proto)

    def to_string(self, proto: Any, buf: bytes) -> str:
        try:
            if len(buf) != 12:  # 10 bytes for address + 2 bytes for port
                raise ValueError("Invalid onion address length")
            # Base32 encode the address
            try:
                addr = base64.b32encode(buf[:10]).decode("ascii").lower()
            except binascii.Error:
                raise ValueError("Invalid base32 encoding")
            # Remove padding
            addr = addr.rstrip("=")
            if len(addr) != 16:
                raise ValueError("Invalid onion address length")
            port = str(int.from_bytes(buf[10:12], byteorder="big"))
            if not 1 <= int(port) <= 65535:
                raise ValueError("Invalid onion port range")
            return f"{addr}:{port}"
        except (ValueError, UnicodeDecodeError, binascii.Error) as e:
            raise BinaryParseError(str(e), buf, proto)
