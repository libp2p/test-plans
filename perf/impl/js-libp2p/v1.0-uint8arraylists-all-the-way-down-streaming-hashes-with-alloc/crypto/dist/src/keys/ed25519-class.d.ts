import type { Multibase } from 'multiformats';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare class Ed25519PublicKey {
    private readonly _key;
    constructor(key: Uint8Array);
    verify(data: Uint8Array | Uint8ArrayList, sig: Uint8Array): Promise<boolean>;
    marshal(): Uint8Array;
    get bytes(): Uint8Array;
    equals(key: any): boolean;
    hash(): Promise<Uint8Array>;
}
export declare class Ed25519PrivateKey {
    private readonly _key;
    private readonly _publicKey;
    constructor(key: Uint8Array, publicKey: Uint8Array);
    sign(message: Uint8Array | Uint8ArrayList): Promise<Uint8Array>;
    get public(): Ed25519PublicKey;
    marshal(): Uint8Array;
    get bytes(): Uint8Array;
    equals(key: any): boolean;
    hash(): Promise<Uint8Array>;
    /**
     * Gets the ID of the key.
     *
     * The key id is the base58 encoding of the identity multihash containing its public key.
     * The public key is a protobuf encoding containing a type and the DER encoding
     * of the PKCS SubjectPublicKeyInfo.
     *
     * @returns {Promise<string>}
     */
    id(): Promise<string>;
    /**
     * Exports the key into a password protected `format`
     */
    export(password: string, format?: string): Promise<Multibase<'m'>>;
}
export declare function unmarshalEd25519PrivateKey(bytes: Uint8Array): Ed25519PrivateKey;
export declare function unmarshalEd25519PublicKey(bytes: Uint8Array): Ed25519PublicKey;
export declare function generateKeyPair(): Promise<Ed25519PrivateKey>;
export declare function generateKeyPairFromSeed(seed: Uint8Array): Promise<Ed25519PrivateKey>;
//# sourceMappingURL=ed25519-class.d.ts.map