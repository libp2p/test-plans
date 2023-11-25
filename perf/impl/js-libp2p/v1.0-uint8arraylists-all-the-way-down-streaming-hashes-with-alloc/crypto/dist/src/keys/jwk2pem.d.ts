import 'node-forge/lib/rsa.js';
export interface JWK {
    encrypt(msg: string): string;
    decrypt(msg: string): string;
}
export declare function jwk2priv(key: JsonWebKey): JWK;
export declare function jwk2pub(key: JsonWebKey): JWK;
//# sourceMappingURL=jwk2pem.d.ts.map