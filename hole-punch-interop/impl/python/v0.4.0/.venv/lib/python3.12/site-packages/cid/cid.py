import base58
from morphys import ensure_bytes, ensure_unicode
import multibase
import multicodec
import multihash as mh


class BaseCID:
    __hash__ = object.__hash__

    def __init__(self, version: int, codec: str, multihash: str | bytes) -> None:
        """
        Creates a new CID object. This class should not be used directly, use
        :py:class:`cid.cid.CIDv0` or :py:class:`cid.cid.CIDv1` instead.


        :param int version: CID version (0 or 1)
        :param str codec: codec to be used for encoding the hash
        :param str multihash: the multihash
        """
        self._version = version
        self._codec = codec
        self._multihash = ensure_bytes(multihash)

    @property
    def version(self) -> int:
        """CID version"""
        return self._version

    @property
    def codec(self) -> str:
        """CID codec"""
        return self._codec

    @property
    def multihash(self) -> bytes:
        """CID multihash"""
        return self._multihash

    @property
    def buffer(self) -> bytes:
        raise NotImplementedError

    def encode(self, encoding: str | None = None) -> bytes:  # noqa: ARG002
        raise NotImplementedError

    def __repr__(self) -> str:
        def truncate(s: bytes, length: int) -> bytes:
            return s[:length] + b".." if len(s) > length else s

        truncate_length = 20
        return (
            f"{self.__class__.__name__}(version={self._version}, "
            f"codec={self._codec}, multihash={truncate(self._multihash, truncate_length)!r})"
        )

    def __str__(self) -> str:
        return ensure_unicode(self.encode())

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, BaseCID):
            return False
        return (
            (self.version == other.version)
            and (self.codec == other.codec)
            and (self.multihash == other.multihash)
        )


class CIDv0(BaseCID):
    """CID version 0 object"""

    CODEC = "dag-pb"

    def __init__(self, multihash: str | bytes) -> None:
        """
        :param bytes multihash: multihash for the CID
        """
        super().__init__(0, self.CODEC, multihash)

    @property
    def buffer(self) -> bytes:
        """
        The raw representation that will be encoded.

        :return: the multihash
        :rtype: bytes
        """
        return self.multihash

    def encode(self, encoding: str | None = None) -> bytes:  # noqa: ARG002
        """
        base58-encoded buffer

        :return: encoded representation or CID
        :rtype: bytes
        """
        return ensure_bytes(base58.b58encode(self.buffer))

    def to_v1(self) -> "CIDv1":
        """
        Get an equivalent :py:class:`cid.CIDv1` object.

        :return: :py:class:`cid.CIDv1` object
        :rtype: :py:class:`cid.CIDv1`
        """
        return CIDv1(self.CODEC, self.multihash)


class CIDv1(BaseCID):
    """CID version 1 object"""

    def __init__(self, codec: str, multihash: str | bytes) -> None:
        super().__init__(1, codec, multihash)

    @property
    def buffer(self) -> bytes:
        """
        The raw representation of the CID

        :return: raw representation of the CID
        :rtype: bytes
        """
        return b"".join([bytes([self.version]), multicodec.add_prefix(self.codec, self.multihash)])

    def encode(self, encoding: str | None = "base58btc") -> bytes:
        """
        Encoded version of the raw representation

        :param str encoding: the encoding to use to encode the raw representation,
            should be supported by ``py-multibase``
        :return: encoded raw representation with the given encoding
        :rtype: bytes
        """
        return multibase.encode(encoding, self.buffer)

    def to_v0(self) -> CIDv0:
        """
        Get an equivalent :py:class:`cid.CIDv0` object.

        :return: :py:class:`cid.CIDv0` object
        :rtype: :py:class:`cid.CIDv0`
        :raise ValueError: if the codec is not 'dag-pb'
        """
        if self.codec != CIDv0.CODEC:
            msg = f"CIDv1 can only be converted for codec {CIDv0.CODEC}"
            raise ValueError(msg)

        return CIDv0(self.multihash)


def make_cid(*args: str | bytes | int) -> CIDv0 | CIDv1:
    """
    Creates a :py:class:`cid.CIDv0` or :py:class:`cid.CIDv1` object based on the given parameters

    The function supports the following signatures:

            make_cid(<base58 encoded multihash CID>) -> CIDv0

            make_cid(<multihash CID>) -> CIDv0

            make_cid(<multibase encoded multihash CID>) -> CIDv1

            make_cid(<version>, <codec>, <multihash>) -> CIDv1

    :param args:
        - base58-encoded multihash (str or bytes)
        - multihash (str or bytes)
        - multibase-encoded multihash (str or bytes)
        - version:int, codec(str), multihash(str or bytes)
    :returns: the respective CID object
    :rtype: :py:class:`cid.CIDv0` or :py:class:`cid.CIDv1`
    :raises ValueError: if the number of arguments is not 1 or 3
    :raises ValueError: if the only argument passed is not a ``str`` or a ``byte``
    :raises ValueError: if the string provided is not a valid base58 encoded hash
    :raises ValueError: if 3 arguments are passed and version is not 0 or 1
    :raises ValueError: if 3 arguments are passed and the ``codec`` is not
        supported by ``multicodec``
    :raises ValueError: if 3 arguments are passed and the ``multihash`` is not ``str`` or ``byte``
    :raises ValueError: if 3 arguments are passed with version 0 and codec is not *dag-pb*
    """
    if len(args) == 1:
        data = args[0]
        if isinstance(data, str):
            return from_string(data)
        if isinstance(data, bytes):
            return from_bytes(data)
        msg = f"invalid argument passed, expected: str or byte, found: {type(data)}"
        raise ValueError(msg)

    if len(args) == 3:
        version, codec, multihash = args
        if version not in (0, 1):
            msg = f"version should be 0 or 1, {version!r} was provided"
            raise ValueError(msg)
        if not isinstance(codec, str):
            msg = "codec must be a string"
            raise ValueError(msg)
        if not multicodec.is_codec(codec):
            msg = f"invalid codec {codec!r} provided, please check"
            raise ValueError(msg)
        if not isinstance(multihash, (str, bytes)):
            msg = "invalid type for multihash provided, should be str or bytes"
            raise ValueError(msg)

        if version == 0:
            if codec != CIDv0.CODEC:
                msg = f"codec for version 0 can only be {CIDv0.CODEC}, found: {codec}"
                raise ValueError(msg)
            return CIDv0(multihash)
        return CIDv1(codec, multihash)
    msg = "invalid number of arguments, expected 1 or 3"
    raise ValueError(msg)


def is_cid(cidstr: str | bytes) -> bool:
    """
    Checks if a given input string is valid encoded CID or not.
    It takes same input as `cid.make_cid` method with a single argument


    :param cidstr: input string which can be a

        - base58-encoded multihash
        - multihash
        - multibase-encoded multihash
    :type cidstr: str or bytes
    :return: if the value is a valid CID or not
    :rtype: bool
    """
    try:
        return bool(make_cid(cidstr))
    except ValueError:
        return False


def from_string(cidstr: str) -> CIDv0 | CIDv1:
    """
    Creates a CID object from a encoded form

    :param str cidstr: can be

        - base58-encoded multihash
        - multihash
        - multibase-encoded multihash
    :return: a CID object
    :rtype: :py:class:`cid.CIDv0` or :py:class:`cid.CIDv1`
    """
    cidbytes = ensure_bytes(cidstr, "utf-8")
    return from_bytes(cidbytes)


def from_bytes(cidbytes: bytes) -> CIDv0 | CIDv1:
    """
    Creates a CID object from a encoded form

    :param bytes cidbytes: can be

        - base58-encoded multihash
        - multihash
        - multibase-encoded multihash
    :return: a CID object
    :rtype: :py:class:`cid.CIDv0` or :py:class:`cid.CIDv1`
    :raises: `ValueError` if the base58-encoded string is not a valid string
    :raises: `ValueError` if the length of the argument is zero
    :raises: `ValueError` if the length of decoded CID is invalid
    """
    if len(cidbytes) < 2:
        msg = "argument length can not be zero"
        raise ValueError(msg)

    # first byte for identity multibase and CIDv0 is 0x00
    # putting in assumption that multibase for CIDv0 can not be identity
    # refer: https://github.com/ipld/cid/issues/13#issuecomment-326490275
    if cidbytes[0] != 0 and multibase.is_encoded(cidbytes):
        # if the bytestream is multibase encoded
        cid = multibase.decode(cidbytes)

        if len(cid) < 2:
            msg = "cid length is invalid"
            raise ValueError(msg)

        data = cid[1:]
        version = int(cid[0])
        codec = multicodec.get_codec(data)
        multihash = multicodec.remove_prefix(data)
    elif cidbytes[0] in (0, 1):
        # if the bytestream is a CID
        version = cidbytes[0]
        data = cidbytes[1:]
        codec = multicodec.get_codec(data)
        multihash = multicodec.remove_prefix(data)
    else:
        # otherwise its just base58-encoded multihash
        try:
            version = 0
            codec = CIDv0.CODEC
            multihash = base58.b58decode(cidbytes)
        except ValueError:
            msg = "multihash is not a valid base58 encoded multihash"
            raise ValueError(msg) from None

    try:
        mh.decode(multihash)
    except ValueError:
        raise

    return make_cid(version, codec, multihash)
