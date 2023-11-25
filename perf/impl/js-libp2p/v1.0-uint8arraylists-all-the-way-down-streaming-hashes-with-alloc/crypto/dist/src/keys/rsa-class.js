import { CodeError } from '@libp2p/interface/errors';
import { sha256 } from 'multiformats/hashes/sha2';
// @ts-expect-error types are missing
import forge from 'node-forge/lib/forge.js';
import { equals as uint8ArrayEquals } from 'uint8arrays/equals';
import 'node-forge/lib/sha512.js';
import { toString as uint8ArrayToString } from 'uint8arrays/to-string';
import { exporter } from './exporter.js';
import * as pbm from './keys.js';
import * as crypto from './rsa.js';
export const MAX_KEY_SIZE = 8192;
export class RsaPublicKey {
    _key;
    constructor(key) {
        this._key = key;
    }
    async verify(data, sig) {
        return crypto.hashAndVerify(this._key, sig, data);
    }
    marshal() {
        return crypto.utils.jwkToPkix(this._key);
    }
    get bytes() {
        return pbm.PublicKey.encode({
            Type: pbm.KeyType.RSA,
            Data: this.marshal()
        }).subarray();
    }
    encrypt(bytes) {
        return crypto.encrypt(this._key, bytes);
    }
    equals(key) {
        return uint8ArrayEquals(this.bytes, key.bytes);
    }
    async hash() {
        const { bytes } = await sha256.digest(this.bytes);
        return bytes;
    }
}
export class RsaPrivateKey {
    _key;
    _publicKey;
    constructor(key, publicKey) {
        this._key = key;
        this._publicKey = publicKey;
    }
    genSecret() {
        return crypto.getRandomValues(16);
    }
    async sign(message) {
        return crypto.hashAndSign(this._key, message);
    }
    get public() {
        if (this._publicKey == null) {
            throw new CodeError('public key not provided', 'ERR_PUBKEY_NOT_PROVIDED');
        }
        return new RsaPublicKey(this._publicKey);
    }
    decrypt(bytes) {
        return crypto.decrypt(this._key, bytes);
    }
    marshal() {
        return crypto.utils.jwkToPkcs1(this._key);
    }
    get bytes() {
        return pbm.PrivateKey.encode({
            Type: pbm.KeyType.RSA,
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
     * Exports the key into a password protected PEM format
     */
    async export(password, format = 'pkcs-8') {
        if (format === 'pkcs-8') {
            const buffer = new forge.util.ByteBuffer(this.marshal());
            const asn1 = forge.asn1.fromDer(buffer);
            const privateKey = forge.pki.privateKeyFromAsn1(asn1);
            const options = {
                algorithm: 'aes256',
                count: 10000,
                saltSize: 128 / 8,
                prfAlgorithm: 'sha512'
            };
            return forge.pki.encryptRsaPrivateKey(privateKey, password, options);
        }
        else if (format === 'libp2p-key') {
            return exporter(this.bytes, password);
        }
        else {
            throw new CodeError(`export format '${format}' is not supported`, 'ERR_INVALID_EXPORT_FORMAT');
        }
    }
}
export async function unmarshalRsaPrivateKey(bytes) {
    const jwk = crypto.utils.pkcs1ToJwk(bytes);
    if (crypto.keySize(jwk) > MAX_KEY_SIZE) {
        throw new CodeError('key size is too large', 'ERR_KEY_SIZE_TOO_LARGE');
    }
    const keys = await crypto.unmarshalPrivateKey(jwk);
    return new RsaPrivateKey(keys.privateKey, keys.publicKey);
}
export function unmarshalRsaPublicKey(bytes) {
    const jwk = crypto.utils.pkixToJwk(bytes);
    if (crypto.keySize(jwk) > MAX_KEY_SIZE) {
        throw new CodeError('key size is too large', 'ERR_KEY_SIZE_TOO_LARGE');
    }
    return new RsaPublicKey(jwk);
}
export async function fromJwk(jwk) {
    if (crypto.keySize(jwk) > MAX_KEY_SIZE) {
        throw new CodeError('key size is too large', 'ERR_KEY_SIZE_TOO_LARGE');
    }
    const keys = await crypto.unmarshalPrivateKey(jwk);
    return new RsaPrivateKey(keys.privateKey, keys.publicKey);
}
export async function generateKeyPair(bits) {
    if (bits > MAX_KEY_SIZE) {
        throw new CodeError('key size is too large', 'ERR_KEY_SIZE_TOO_LARGE');
    }
    const keys = await crypto.generateKey(bits);
    return new RsaPrivateKey(keys.privateKey, keys.publicKey);
}
//# sourceMappingURL=rsa-class.js.map