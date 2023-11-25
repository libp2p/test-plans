import 'node-forge/lib/sha512.js';
import type { Multibase } from 'multiformats';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare const MAX_KEY_SIZE = 8192;
export declare class RsaPublicKey {
    private readonly _key;
    constructor(key: JsonWebKey);
    verify(data: Uint8Array | Uint8ArrayList, sig: Uint8Array): Promise<boolean>;
    marshal(): Uint8Array;
    get bytes(): Uint8Array;
    encrypt(bytes: Uint8Array | Uint8ArrayList): Uint8Array;
    equals(key: any): boolean;
    hash(): Promise<Uint8Array>;
}
export declare class RsaPrivateKey {
    private readonly _key;
    private readonly _publicKey;
    constructor(key: JsonWebKey, publicKey: JsonWebKey);
    genSecret(): Uint8Array;
    sign(message: Uint8Array | Uint8ArrayList): Promise<Uint8Array>;
    get public(): RsaPublicKey;
    decrypt(bytes: Uint8Array | Uint8ArrayList): Uint8Array;
    marshal(): Uint8Array;
    get bytes(): Uint8Array;
    equals(key: any): boolean;
    hash(): Promise<Uint8Array>;
    /**
     * Gets the ID of the key.
     *
     * The key id is the base58 encoding of the SHA-256 multihash of its public key.
     * The public key is a protobuf encoding containing a type and the DER encoding
     * of the PKCS SubjectPublicKeyInfo.
     */
    id(): Promise<string>;
    /**
     * Exports the key into a password protected PEM format
     */
    export(password: string, format?: string): Promise<Multibase<'m'>>;
}
export declare function unmarshalRsaPrivateKey(bytes: Uint8Array): Promise<RsaPrivateKey>;
export declare function unmarshalRsaPublicKey(bytes: Uint8Array): RsaPublicKey;
export declare function fromJwk(jwk: JsonWebKey): Promise<RsaPrivateKey>;
export declare function generateKeyPair(bits: number): Promise<RsaPrivateKey>;
//# sourceMappingURL=rsa-class.d.ts.map