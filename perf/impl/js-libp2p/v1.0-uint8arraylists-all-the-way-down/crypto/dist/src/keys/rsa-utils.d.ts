import 'node-forge/lib/asn1.js';
import 'node-forge/lib/rsa.js';
export declare function pkcs1ToJwk(bytes: Uint8Array): JsonWebKey;
export declare function jwkToPkcs1(jwk: JsonWebKey): Uint8Array;
export declare function pkixToJwk(bytes: Uint8Array): JsonWebKey;
export declare function jwkToPkix(jwk: JsonWebKey): Uint8Array;
//# sourceMappingURL=rsa-utils.d.ts.map