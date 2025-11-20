import base64
import binascii
from typing import Any

from ..codecs import CodecBase

SIZE = -1
IS_PATH = False


class Codec(CodecBase):
    """
    Codec for I2P garlic64 addresses.

    garlic64 is a custom Base64 encoding used by I2P with an alternate
    character set ('-~' instead of '+/'). The decoded addresses have a
    minimum byte length of 386.
    """

    SIZE = SIZE
    IS_PATH = IS_PATH

    def validate(self, b: bytes) -> None:
        """
        Validates that the byte representation of a garlic64 address is valid.
        According to the go-multiaddr implementation, the decoded byte array
        must be at least 386 bytes long.

        Args:
            b: The bytes to validate.

        Raises:
            ValueError: If the byte length is less than 386.
        """
        # A garlic64 address will always be at least 386 bytes long when decoded.
        if len(b) < 386:
            raise ValueError(
                f"Invalid length for garlic64: must be at least 386 bytes, got {len(b)}"
            )

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """
        Converts the string representation of a garlic64 address to bytes.
        This involves decoding the string using the I2P-specific Base64
        alphabet and then validating the resulting bytes.

        Args:
            proto: The multiaddr protocol code (unused).
            string: The string representation of the address.

        Returns:
            The byte representation of the address.

        Raises:
            ValueError: If the string is not valid Base64 or fails validation.
        """
        try:
            # Decode using the I2P garlic alphabet by replacing '+' with '-' and '/' with '~'.
            decoded_bytes = base64.b64decode(string, altchars=b"-~")
        except (ValueError, binascii.Error) as e:
            # Catch potential padding errors or invalid characters.
            raise ValueError(f"Failed to decode base64 i2p addr: {string}") from e

        # Validate the decoded bytes *after* decoding, as per the Go implementation.
        self.validate(decoded_bytes)
        return decoded_bytes

    def to_string(self, proto: Any, buf: bytes) -> str:
        """
        Converts the byte representation of a garlic64 address to its string form.
        This involves validating the bytes first and then encoding them using
        the I2P-specific Base64 alphabet.

        Args:
            proto: The multiaddr protocol code (unused).
            buf: The byte representation of the address.

        Returns:
            The string representation of the address.
        """
        # Validate the bytes *before* encoding, as per the Go implementation.
        self.validate(buf)

        # Encode using the I2P garlic alphabet. The result is bytes, so decode to UTF-8.
        addr_string = base64.b64encode(buf, altchars=b"-~").decode("utf-8")
        return addr_string
