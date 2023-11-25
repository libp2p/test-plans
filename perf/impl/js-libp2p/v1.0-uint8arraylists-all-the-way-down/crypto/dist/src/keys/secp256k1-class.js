import { CodeError } from '@libp2p/interface/errors';
import { sha256 } from 'multiformats/hashes/sha2';
import { equals as uint8ArrayEquals } from 'uint8arrays/equals';
import { toString as uint8ArrayToString } from 'uint8arrays/to-string';
import { exporter } from './exporter.js';
import * as keysProtobuf from './keys.js';
import * as crypto from './secp256k1.js';
export class Secp256k1PublicKey {
    _key;
    constructor(key) {
        crypto.validatePublicKey(key);
        this._key = key;
    }
    async verify(data, sig) {
        return crypto.hashAndVerify(this._key, sig, data);
    }
    marshal() {
        return crypto.compressPublicKey(this._key);
    }
    get bytes() {
        return keysProtobuf.PublicKey.encode({
            Type: keysProtobuf.KeyType.Secp256k1,
            Data: this.marshal()
        }).subarray();
    }
    equals(key) {
        return uint8ArrayEquals(this.bytes, key.bytes);
    }
    async hash() {
        const { bytes } = await sha256.digest(this.bytes);
        return bytes;
    }
}
export class Secp256k1PrivateKey {
    _key;
    _publicKey;
    constructor(key, publicKey) {
        this._key = key;
        this._publicKey = publicKey ?? crypto.computePublicKey(key);
        crypto.validatePrivateKey(this._key);
        crypto.validatePublicKey(this._publicKey);
    }
    async sign(message) {
        return crypto.hashAndSign(this._key, message);
    }
    get public() {
        return new Secp256k1PublicKey(this._publicKey);
    }
    marshal() {
        return this._key;
    }
    get bytes() {
        return keysProtobuf.PrivateKey.encode({
            Type: keysProtobuf.KeyType.Secp256k1,
            Data: this.marshal()
        }).subarray();
    }
    equals(key) {
        return uint8ArrayEquals(this.bytes, key.bytes);
    }
    async hash() {
        const { bytes } = await sha256.digest(this.bytes);
        return bytes;
    }
    /**
     * Gets the ID of the key.
     *
     * The key id is the base58 encoding of the SHA-256 multihash of its public key.
     * The public key is a protobuf encoding containing a type and the DER encoding
     * of the PKCS SubjectPublicKeyInfo.
     */
    async id() {
        const hash = await this.public.hash();
        return uint8ArrayToString(hash, 'base58btc');
    }
    /**
     * Exports the key into a password protected `format`
     */
    async export(password, format = 'libp2p-key') {
        if (format === 'libp2p-key') {
            return exporter(this.bytes, password);
        }
        else {
            throw new CodeError(`export format '${format}' is not supported`, 'ERR_INVALID_EXPORT_FORMAT');
        }
    }
}
export function unmarshalSecp256k1PrivateKey(bytes) {
    return new Secp256k1PrivateKey(bytes);
}
export function unmarshalSecp256k1PublicKey(bytes) {
    return new Secp256k1PublicKey(bytes);
}
export async function generateKeyPair() {
    const privateKeyBytes = crypto.generateKey();
    return new Secp256k1PrivateKey(privateKeyBytes);
}
//# sourceMappingURL=secp256k1-class.js.map