import randomBytes from '../random-bytes.js';
import * as utils from './rsa-utils.js';
import type { JWKKeyPair } from './interface.js';
import type { Uint8ArrayList } from 'uint8arraylist';
export { utils };
export declare function generateKey(bits: number): Promise<JWKKeyPair>;
export declare function unmarshalPrivateKey(key: JsonWebKey): Promise<JWKKeyPair>;
export { randomBytes as getRandomValues };
export declare function hashAndSign(key: JsonWebKey, msg: Uint8Array | Uint8ArrayList): Promise<Uint8Array>;
export declare function hashAndVerify(key: JsonWebKey, sig: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<boolean>;
export declare function encrypt(key: JsonWebKey, msg: Uint8Array | Uint8ArrayList): Uint8Array;
export declare function decrypt(key: JsonWebKey, msg: Uint8Array | Uint8ArrayList): Uint8Array;
export declare function keySize(jwk: JsonWebKey): number;
//# sourceMappingURL=rsa-browser.d.ts.map