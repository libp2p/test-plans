import type { Uint8ArrayList } from 'uint8arraylist';
declare const PRIVATE_KEY_BYTE_LENGTH = 32;
export { PRIVATE_KEY_BYTE_LENGTH as privateKeyLength };
export declare function generateKey(): Uint8Array;
/**
 * Hash and sign message with private key
 */
export declare function hashAndSign(key: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<Uint8Array>;
/**
 * Hash message and verify signature with public key
 */
export declare function hashAndVerify(key: Uint8Array, sig: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<boolean>;
export declare function compressPublicKey(key: Uint8Array): Uint8Array;
export declare function decompressPublicKey(key: Uint8Array): Uint8Array;
export declare function validatePrivateKey(key: Uint8Array): void;
export declare function validatePublicKey(key: Uint8Array): void;
export declare function computePublicKey(privateKey: Uint8Array): Uint8Array;
//# sourceMappingURL=secp256k1-browser.d.ts.map