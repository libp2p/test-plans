import { type Uint8ArrayList } from 'uint8arraylist';
import type { bytes32 } from './@types/basic.js';
import type { Hkdf } from './@types/handshake.js';
import type { KeyPair } from './@types/libp2p.js';
export interface ICryptoInterface {
    hashSHA256: (data: Uint8Array | Uint8ArrayList) => Uint8Array;
    getHKDF: (ck: bytes32, ikm: Uint8Array) => Hkdf;
    generateX25519KeyPair: () => KeyPair;
    generateX25519KeyPairFromSeed: (seed: Uint8Array) => KeyPair;
    generateX25519SharedKey: (privateKey: Uint8Array | Uint8ArrayList, publicKey: Uint8Array | Uint8ArrayList) => Uint8Array;
    chaCha20Poly1305Encrypt: (plaintext: Uint8Array | Uint8ArrayList, nonce: Uint8Array, ad: Uint8Array, k: bytes32) => Uint8ArrayList | Uint8Array;
    chaCha20Poly1305Decrypt: (ciphertext: Uint8Array | Uint8ArrayList, nonce: Uint8Array, ad: Uint8Array, k: bytes32, dst?: Uint8Array) => Uint8ArrayList | Uint8Array | null;
}
//# sourceMappingURL=crypto.d.ts.map