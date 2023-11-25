/**
 * @packageDocumentation
 *
 * **Supported Key Types**
 *
 * The {@link generateKeyPair}, {@link marshalPublicKey}, and {@link marshalPrivateKey} functions accept a string `type` argument.
 *
 * Currently the `'RSA'`, `'ed25519'`, and `secp256k1` types are supported, although ed25519 and secp256k1 keys support only signing and verification of messages.
 *
 * For encryption / decryption support, RSA keys should be used.
 */
import 'node-forge/lib/asn1.js';
import 'node-forge/lib/pbe.js';
import * as Ed25519 from './ed25519-class.js';
import generateEphemeralKeyPair from './ephemeral-keys.js';
import { keyStretcher } from './key-stretcher.js';
import * as keysPBM from './keys.js';
import * as RSA from './rsa-class.js';
import * as Secp256k1 from './secp256k1-class.js';
import type { PrivateKey, PublicKey } from '@libp2p/interface/keys';
export { keyStretcher };
export { generateEphemeralKeyPair };
export { keysPBM };
export type KeyTypes = 'RSA' | 'Ed25519' | 'secp256k1';
export declare const supportedKeys: {
    rsa: typeof RSA;
    ed25519: typeof Ed25519;
    secp256k1: typeof Secp256k1;
};
/**
 * Generates a keypair of the given type and bitsize
 *
 * @param type
 * @param bits -  Minimum of 1024
 */
export declare function generateKeyPair(type: KeyTypes, bits?: number): Promise<PrivateKey>;
/**
 * Generates a keypair of the given type and bitsize.
 *
 * Seed is a 32 byte uint8array
 */
export declare function generateKeyPairFromSeed(type: KeyTypes, seed: Uint8Array, bits?: number): Promise<PrivateKey>;
/**
 * Converts a protobuf serialized public key into its representative object
 */
export declare function unmarshalPublicKey(buf: Uint8Array): PublicKey;
/**
 * Converts a public key object into a protobuf serialized public key
 */
export declare function marshalPublicKey(key: {
    bytes: Uint8Array;
}, type?: string): Uint8Array;
/**
 * Converts a protobuf serialized private key into its representative object
 */
export declare function unmarshalPrivateKey(buf: Uint8Array): Promise<PrivateKey>;
/**
 * Converts a private key object into a protobuf serialized private key
 */
export declare function marshalPrivateKey(key: {
    bytes: Uint8Array;
}, type?: string): Uint8Array;
/**
 * Converts an exported private key into its representative object.
 *
 * Supported formats are 'pem' (RSA only) and 'libp2p-key'.
 */
export declare function importKey(encryptedKey: string, password: string): Promise<PrivateKey>;
//# sourceMappingURL=index.d.ts.map