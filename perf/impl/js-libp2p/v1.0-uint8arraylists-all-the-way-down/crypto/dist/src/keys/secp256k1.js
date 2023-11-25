import crypto from 'node:crypto';
import { CodeError } from '@libp2p/interface/errors';
import { secp256k1 as secp } from '@noble/curves/secp256k1';
const PRIVATE_KEY_BYTE_LENGTH = 32;
export { PRIVATE_KEY_BYTE_LENGTH as privateKeyLength };
export function generateKey() {
    return secp.utils.randomPrivateKey();
}
/**
 * Hash and sign message with private key
 */
export async function hashAndSign(key, msg) {
    const hash = crypto.createHash('sha256');
    if (msg instanceof Uint8Array) {
        hash.update(msg);
    }
    else {
        for (const buf of msg) {
            hash.update(buf);
        }
    }
    const digest = hash.digest();
    try {
        const signature = secp.sign(digest, key);
        return signature.toDERRawBytes();
    }
    catch (err) {
        throw new CodeError(String(err), 'ERR_INVALID_INPUT');
    }
}
/**
 * Hash message and verify signature with public key
 */
export async function hashAndVerify(key, sig, msg) {
    const hash = crypto.createHash('sha256');
    if (msg instanceof Uint8Array) {
        hash.update(msg);
    }
    else {
        for (const buf of msg) {
            hash.update(buf);
        }
    }
    const digest = hash.digest();
    try {
        return secp.verify(sig, digest, key);
    }
    catch (err) {
        throw new CodeError(String(err), 'ERR_INVALID_INPUT');
    }
}
export function compressPublicKey(key) {
    const point = secp.ProjectivePoint.fromHex(key).toRawBytes(true);
    return point;
}
export function decompressPublicKey(key) {
    const point = secp.ProjectivePoint.fromHex(key).toRawBytes(false);
    return point;
}
export function validatePrivateKey(key) {
    try {
        secp.getPublicKey(key, true);
    }
    catch (err) {
        throw new CodeError(String(err), 'ERR_INVALID_PRIVATE_KEY');
    }
}
export function validatePublicKey(key) {
    try {
        secp.ProjectivePoint.fromHex(key);
    }
    catch (err) {
        throw new CodeError(String(err), 'ERR_INVALID_PUBLIC_KEY');
    }
}
export function computePublicKey(privateKey) {
    try {
        return secp.getPublicKey(privateKey, true);
    }
    catch (err) {
        throw new CodeError(String(err), 'ERR_INVALID_PRIVATE_KEY');
    }
}
//# sourceMappingURL=secp256k1.js.map