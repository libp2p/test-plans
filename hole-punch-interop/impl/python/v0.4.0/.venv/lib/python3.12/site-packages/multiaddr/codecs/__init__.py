import importlib
from typing import Any

# These are special sizes
LENGTH_PREFIXED_VAR_SIZE = -1


class CodecBase:
    SIZE: int
    IS_PATH: bool

    def to_string(self, proto: Any, buf: bytes) -> str:
        raise NotImplementedError

    def to_bytes(self, proto: Any, string: str) -> bytes:
        raise NotImplementedError


class NoneCodec(CodecBase):
    SIZE: int = 0
    IS_PATH: bool = False

    def to_string(self, proto: Any, buf: bytes) -> str:
        return ""

    def to_bytes(self, proto: Any, string: str) -> bytes:
        return b""


CODEC_CACHE: dict[str, CodecBase] = {}


def codec_by_name(name: str | None) -> CodecBase:
    if name is None:  # Special "do nothing - expect nothing" pseudo-codec
        return NoneCodec()
    codec = CODEC_CACHE.get(name)
    if codec is None:
        module = importlib.import_module(f".{name}", __name__)
        codec_class = getattr(module, "Codec")
        assert codec_class is not None, f"Codec {name} not found"
        codec = codec_class()
        CODEC_CACHE[name] = codec
    return codec
