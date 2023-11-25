import 'node-forge/lib/aes.js';
export interface Cipher {
    update(data: Uint8Array): Uint8Array;
}
export declare function createCipheriv(mode: any, key: Uint8Array, iv: Uint8Array): Cipher;
export declare function createDecipheriv(mode: any, key: Uint8Array, iv: Uint8Array): Cipher;
//# sourceMappingURL=ciphers-browser.d.ts.map