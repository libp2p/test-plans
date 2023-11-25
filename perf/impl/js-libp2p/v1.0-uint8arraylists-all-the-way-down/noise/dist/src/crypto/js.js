import { chacha20poly1305 } from '@noble/ciphers/chacha';
import { x25519 } from '@noble/curves/ed25519';
import { extract, expand } from '@noble/hashes/hkdf';
import { sha256 } from '@noble/hashes/sha256';
export const pureJsCrypto = {
    hashSHA256(data) {
        return sha256(data.subarray());
    },
    getHKDF(ck, ikm) {
        const prk = extract(sha256, ikm, ck);
        const okmU8Array = expand(sha256, prk, undefined, 96);
        const okm = okmU8Array;
        const k1 = okm.subarray(0, 32);
        const k2 = okm.subarray(32, 64);
        const k3 = okm.subarray(64, 96);
        return [k1, k2, k3];
    },
    generateX25519KeyPair() {
        const secretKey = x25519.utils.randomPrivateKey();
        const publicKey = x25519.getPublicKey(secretKey);
        return {
            publicKey,
            privateKey: secretKey
        };
    },
    generateX25519KeyPairFromSeed(seed) {
        const publicKey = x25519.getPublicKey(seed);
        return {
            publicKey,
            privateKey: seed
        };
    },
    generateX25519SharedKey(privateKey, publicKey) {
        return x25519.getSharedSecret(privateKey.subarray(), publicKey.subarray());
    },
    chaCha20Poly1305Encrypt(plaintext, nonce, ad, k) {
        return chacha20poly1305(k, nonce, ad).encrypt(plaintext.subarray());
    },
    chaCha20Poly1305Decrypt(ciphertext, nonce, ad, k, dst) {
        return chacha20poly1305(k, nonce, ad).decrypt(ciphertext.subarray(), dst);
    }
};
//# sourceMappingURL=js.js.map