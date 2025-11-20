from typing import Any

import netaddr

from ..codecs import CodecBase
from ..exceptions import BinaryParseError

SIZE = 32
IS_PATH = False


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        return netaddr.IPAddress(string, version=4).packed

    def to_string(self, proto: Any, buf: bytes) -> str:
        try:
            return str(netaddr.IPAddress(int.from_bytes(buf, byteorder="big"), version=4))
        except (ValueError, netaddr.AddrFormatError):
            raise BinaryParseError("Invalid IPv4 address bytes", buf, "ip4")
