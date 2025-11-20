import base64
import binascii
from typing import Any

from ..codecs import CodecBase

# A garlic32 address is variable-length, so we set SIZE to -1.
SIZE = -1
IS_PATH = False


class Codec(CodecBase):
    """
    Codec for I2P garlic32 addresses
    """

    SIZE = SIZE
    IS_PATH = IS_PATH

    def validate(self, b: bytes) -> None:
        """
        Validates the byte representation of a garlic32 address.
        According to the go-multiaddr implementation, the decoded byte array
        must be exactly 32 bytes long, or >= 35 bytes long.

        Args:
            b: The bytes to validate.

        Raises:
            ValueError: If the byte length is invalid.
        """
        # https://geti2p.net/spec/b32encrypted
        if not (len(b) == 32 or len(b) >= 35):
            raise ValueError(
                f"Invalid length for garlic32: must be 32 or >= 35 bytes, got {len(b)}"
            )

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """
        Converts the string representation of a garlic32 address to bytes.
        This involves handling the lowercase alphabet, adding necessary padding,
        decoding, and then validating the resulting bytes.

        Args:
            proto: The multiaddr protocol code (unused).
            string: The string representation of the address.

        Returns:
            The byte representation of the address.

        Raises:
            ValueError: If the string is not valid Base32 or fails validation.
        """
        # The Go implementation uses a lowercase alphabet, but Python's b32decode
        # expects uppercase.
        s_upper = string.upper()

        # Add padding if it was stripped during encoding. Base32 requires
        # the input length to be a multiple of 8.
        padding = "=" * (-len(s_upper) % 8)
        s_padded = s_upper + padding

        try:
            decoded_bytes = base64.b32decode(s_padded)
        except (ValueError, binascii.Error) as e:
            raise ValueError(f"Failed to decode base32 i2p addr: {string}") from e

        # Validate the decoded bytes after decoding.
        self.validate(decoded_bytes)
        return decoded_bytes

    def to_string(self, proto: Any, buf: bytes) -> str:
        """
        Converts the byte representation of a garlic32 address to its string form.
        This involves validating the bytes, encoding them, converting to lowercase,
        and stripping any padding characters.

        Args:
            proto: The multiaddr protocol code (unused).
            buf: The byte representation of the address.

        Returns:
            The string representation of the address.
        """
        # Validate the bytes before encoding.
        self.validate(buf)

        # Encode to Base32, which produces an uppercase string with padding.
        encoded_bytes = base64.b32encode(buf)
        addr_string = encoded_bytes.decode("utf-8")

        # The Go implementation uses a lowercase alphabet and trims padding.
        return addr_string.lower().rstrip("=")
