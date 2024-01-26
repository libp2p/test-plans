import { type Codec } from 'protons-runtime';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare enum KeyType {
    RSA = "RSA",
    Ed25519 = "Ed25519",
    Secp256k1 = "Secp256k1",
    ECDSA = "ECDSA"
}
export declare namespace KeyType {
    const codec: () => Codec<KeyType>;
}
export interface PublicKey {
    type?: KeyType;
    data?: Uint8Array;
}
export declare namespace PublicKey {
    const codec: () => Codec<PublicKey>;
    const encode: (obj: Partial<PublicKey>) => Uint8Array;
    const decode: (buf: Uint8Array | Uint8ArrayList) => PublicKey;
}
//# sourceMappingURL=index.d.ts.map