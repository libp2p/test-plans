import type { Multibase } from 'multiformats';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare class Secp256k1PublicKey {
    private readonly _key;
    constructor(key: Uint8Array);
    verify(data: Uint8Array | Uint8ArrayList, sig: Uint8Array): Promise<boolean>;
    marshal(): Uint8Array;
    get bytes(): Uint8Array;
    equals(key: any): boolean;
    hash(): Promise<Uint8Array>;
}
export declare class Secp256k1PrivateKey {
    private readonly _key;
    private readonly _publicKey;
    constructor(key: Uint8Array, publicKey?: Uint8Array);
    sign(message: Uint8Array | Uint8ArrayList): Promise<Uint8Array>;
    get public(): Secp256k1PublicKey;
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
     * Exports the key into a password protected `format`
     */
    export(password: string, format?: string): Promise<Multibase<'m'>>;
}
export declare function unmarshalSecp256k1PrivateKey(bytes: Uint8Array): Secp256k1PrivateKey;
export declare function unmarshalSecp256k1PublicKey(bytes: Uint8Array): Secp256k1PublicKey;
export declare function generateKeyPair(): Promise<Secp256k1PrivateKey>;
//# sourceMappingURL=secp256k1-class.d.ts.map