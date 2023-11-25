/// <reference types="node" />
import type { Uint8ArrayKeyPair } from './interface.js';
import type { Uint8ArrayList } from 'uint8arraylist';
declare const PUBLIC_KEY_BYTE_LENGTH = 32;
declare const PRIVATE_KEY_BYTE_LENGTH = 64;
export { PUBLIC_KEY_BYTE_LENGTH as publicKeyLength };
export { PRIVATE_KEY_BYTE_LENGTH as privateKeyLength };
export declare function generateKey(): Promise<Uint8ArrayKeyPair>;
/**
 * Generate keypair from a 32 byte uint8array
 */
export declare function generateKeyFromSeed(seed: Uint8Array): Promise<Uint8ArrayKeyPair>;
export declare function hashAndSign(key: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<Buffer>;
export declare function hashAndVerify(key: Uint8Array, sig: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<boolean>;
//# sourceMappingURL=ed25519.d.ts.map