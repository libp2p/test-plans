import logging
from typing import Any

import base58
import cid

from ..codecs import CodecBase
from ..exceptions import BinaryParseError
from . import LENGTH_PREFIXED_VAR_SIZE

logger = logging.getLogger(__name__)

SIZE = LENGTH_PREFIXED_VAR_SIZE
IS_PATH = False


# Spec: https://github.com/libp2p/specs/blob/master/peer-ids/peer-ids.md#string-representation
CIDv0_PREFIX_TO_LENGTH: dict[str, list[int]] = {
    # base58btc prefixes for valid lengths 1 - 42 with the identity "hash" function
    "12": [5, 12, 19, 23, 30, 41, 52, 56],
    "13": [9, 16, 34, 45],
    "14": [27, 38, 49, 60],
    "15": [3, 6, 20],
    "16": [3, 6, 13, 20, 31, 42, 53],
    "17": [3, 13, 42],
    "18": [3],
    "19": [3, 24, 57],
    "1A": [24, 35, 46],
    "1B": [35],
    "1D": [17],
    "1E": [10, 17],
    "1F": [10],
    "1G": [10, 28, 50],
    "1H": [28, 39],
    "1P": [21],
    "1Q": [21],
    "1R": [21, 54],
    "1S": [54],
    "1T": [7, 32, 43],
    "1U": [7, 32, 43],
    "1V": [7],
    "1W": [7, 14],
    "1X": [7, 14],
    "1Y": [7, 14],
    "1Z": [7, 14],
    "1f": [4],
    "1g": [4, 58],
    "1h": [4, 25, 58],
    "1i": [4, 25],
    "1j": [4, 25],
    "1k": [4, 25, 47],
    "1m": [4, 36, 47],
    "1n": [4, 36],
    "1o": [4, 36],
    "1p": [4],
    "1q": [4],
    "1r": [4],
    "1s": [4],
    "1t": [4],
    "1u": [4],
    "1v": [4],
    "1w": [4],
    "1x": [4],
    "1y": [4],
    "1z": [4, 18],
    # base58btc prefix for length 42 with the sha256 hash function
    "Qm": [46],
}

PROTO_NAME_TO_CIDv1_CODEC = {
    "p2p": "libp2p-key",
    "ipfs": "dag-pb",
}


def _is_binary_cidv0_multihash(buf: bytes) -> bool:
    """Check if the given bytes represent a CIDv0 multihash."""
    try:
        # CIDv0 is just a base58btc encoded multihash
        # The first byte is the hash function code, second byte is the length
        if len(buf) < 2:
            return False
        hash_code = buf[0]
        length = buf[1]
        if len(buf) != length + 2:  # +2 for the hash code and length bytes
            return False
        # For CIDv0, we only support sha2-256 (0x12) and identity (0x00)
        return hash_code in (0x12, 0x00)
    except Exception:
        return False


class Codec(CodecBase):
    SIZE = SIZE
    IS_PATH = IS_PATH

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """Convert a CID string to its binary representation."""
        if not string:
            raise ValueError("CID string cannot be empty")

        logger.debug(f"[DEBUG CID to_bytes] Input value: {string}")

        # First try to parse as CIDv0 (base58btc encoded multihash)
        try:
            decoded = base58.b58decode(string)
            if _is_binary_cidv0_multihash(decoded):
                logger.debug(f"[DEBUG CID to_bytes] Parsed as CIDv0: {decoded.hex()}")
                # Do not add length prefix here; the framework handles it
                return decoded
        except Exception as e:
            logger.debug(f"[DEBUG CID to_bytes] Failed to parse as CIDv0: {e}")

        # If not CIDv0, try to parse as CIDv1
        try:
            parsed = cid.make_cid(string)

            # Do not add length prefix here; the framework handles it
            if not isinstance(parsed.buffer, bytes):
                raise ValueError("CID buffer must be bytes")
            return parsed.buffer
        except ValueError as e:
            logger.debug(f"[DEBUG CID to_bytes] Failed to parse as CIDv1: {e}")
            raise ValueError(f"Invalid CID: {string}")

    def to_string(self, proto: Any, buf: bytes) -> str:
        """Convert a binary CID to its string representation."""
        if not buf:
            raise ValueError("CID buffer cannot be empty")

        logger.debug(f"[DEBUG CID to_string] Input buffer: {buf.hex()}")
        logger.debug(f"[DEBUG CID to_string] Protocol: {proto.name}")

        expected_codec = PROTO_NAME_TO_CIDv1_CODEC.get(proto.name)
        logger.debug(f"[DEBUG CID to_string] Expected codec: {expected_codec}")

        try:
            # First try to parse as CIDv0
            if _is_binary_cidv0_multihash(buf):
                result = base58.b58encode(buf).decode("ascii")
                logger.debug(f"[DEBUG CID to_string] Parsed as CIDv0: {result}")
                return result

            # If not CIDv0, try to parse as CIDv1
            parsed = cid.from_bytes(buf)
            logger.debug(f"[DEBUG CID to_string] Parsed as CIDv1: {parsed}")

            # Ensure CID has correct codec for protocol
            if expected_codec and parsed.codec != expected_codec:
                raise ValueError(
                    '"{}" multiaddr CIDs must use the "{}" multicodec'.format(
                        proto.name, expected_codec
                    )
                )

            # For peer IDs (p2p/ipfs), always try to use CIDv0 format if possible
            if expected_codec:
                # Try to convert to CIDv0 format
                try:
                    # Extract the multihash bytes
                    multihash = parsed.multihash
                    logger.debug(f"[DEBUG CID to_string] Extracted multihash: {multihash.hex()}")
                    # Check if it's a valid CIDv0 multihash
                    if _is_binary_cidv0_multihash(multihash):
                        result = base58.b58encode(multihash).decode("ascii")
                        logger.debug(f"[DEBUG CID to_string] Converted to CIDv0: {result}")
                        return result
                except Exception as e:
                    logger.debug(f"[DEBUG CID to_string] Failed to convert to CIDv0: {e}")

            # If we can't convert to CIDv0, use base32 CIDv1 format
            result = parsed.encode("base32").decode("ascii")
            logger.debug(f"[DEBUG CID to_string] Using CIDv1 format: {result}")
            return result
        except Exception as e:
            logger.debug(f"[DEBUG CID to_string] Error: {e}")
            raise BinaryParseError(str(e), buf, proto.name, e) from e
