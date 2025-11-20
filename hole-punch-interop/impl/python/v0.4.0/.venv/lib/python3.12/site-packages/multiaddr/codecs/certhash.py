from typing import Any

import multibase
import multihash

from ..codecs import CodecBase

SIZE = -1
IS_PATH = False


class Codec(CodecBase):
    """
    Codec for certificate hashes (certhash).

    A certhash is a multihash of a certificate, encoded as a multibase string
    using the 'base64url' encoding.
    """

    SIZE = SIZE
    IS_PATH = IS_PATH

    def validate(self, b: bytes) -> None:
        """
        Validates that the byte representation is a valid multihash.

        Args:
            b: The bytes to validate.

        Raises:
            ValueError: If the bytes cannot be decoded as a multihash.
        """
        try:
            multihash.decode(b)
        except Exception as e:
            raise ValueError("Invalid certhash: not a valid multihash") from e

    def to_bytes(self, proto: Any, string: str) -> bytes:
        """
        Converts the multibase string representation of a certhash to bytes.

        This involves decoding the multibase string and then validating that
        the resulting bytes are a valid multihash.

        Args:
            proto: The multiaddr protocol code (unused).
            string: The string representation of the certhash.

        Returns:
            The raw multihash bytes.

        Raises:
            ValueError: If the string is not valid multibase or not a multihash.
        """
        try:
            # Decode the multibase string to get the raw multihash bytes.
            decoded_bytes = multibase.decode(string)
        except Exception as e:
            raise ValueError(f"Failed to decode multibase string: {string}") from e

        # Validate that the decoded bytes are a valid multihash.
        self.validate(decoded_bytes)
        return decoded_bytes

    def to_string(self, proto: Any, buf: bytes) -> str:
        """
        Converts the raw multihash bytes of a certhash to its string form.

        This involves validating the bytes first and then encoding them as a
        'base64url' multibase string.

        Args:
            proto: The multiaddr protocol code (unused).
            buf: The raw multihash bytes.

        Returns:
            The multibase string representation of the certhash.
        """
        # Validate the bytes before encoding.
        self.validate(buf)

        # Encode the bytes using base64url, which is standard for certhash.
        # The result from `multibase.encode` is bytes, so we decode to a string.
        encoded_string = multibase.encode("base64url", buf)
        return encoded_string.decode("utf-8")
