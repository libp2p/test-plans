from typing import Any

import netaddr

from ..codecs import CodecBase

SIZE = 128
IS_PATH = False


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        return netaddr.IPAddress(string, version=6).packed

    def to_string(self, proto: Any, buf: bytes) -> str:
        return str(netaddr.IPAddress(int.from_bytes(buf, byteorder="big"), version=6))
