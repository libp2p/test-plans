import struct
from typing import Any

from ..codecs import CodecBase
from ..exceptions import BinaryParseError

SIZE = 64
IS_PATH = False


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        # Parse as unsigned 64-bit int
        value = int(string, 10)
        if value < 0 or value > 0xFFFFFFFFFFFFFFFF:
            raise ValueError("Value out of range for uint64")
        return struct.pack(">Q", value)  # big-endian uint64

    def to_string(self, proto: Any, buf: bytes) -> str:
        if len(buf) != 8:
            raise BinaryParseError("Expected 8 bytes for uint64", buf, "memory")
        value = struct.unpack(">Q", buf)[0]
        return str(value)

    def memory_validate(self, b: bytes) -> None:
        if len(b) != 8:
            raise ValueError(f"Invalid length: must be exactly 8 bytes, got {len(b)}")
