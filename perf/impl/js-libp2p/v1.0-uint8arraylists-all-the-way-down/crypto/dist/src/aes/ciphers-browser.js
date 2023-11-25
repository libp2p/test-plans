import 'node-forge/lib/aes.js';
// @ts-expect-error types are missing
import forge from 'node-forge/lib/forge.js';
import { fromString as uint8ArrayFromString } from 'uint8arrays/from-string';
import { toString as uint8ArrayToString } from 'uint8arrays/to-string';
export function createCipheriv(mode, key, iv) {
    const cipher2 = forge.cipher.createCipher('AES-CTR', uint8ArrayToString(key, 'ascii'));
    cipher2.start({ iv: uint8ArrayToString(iv, 'ascii') });
    return {
        update: (data) => {
            cipher2.update(forge.util.createBuffer(uint8ArrayToString(data, 'ascii')));
            return uint8ArrayFromString(cipher2.output.getBytes(), 'ascii');
        }
    };
}
export function createDecipheriv(mode, key, iv) {
    const cipher2 = forge.cipher.createDecipher('AES-CTR', uint8ArrayToString(key, 'ascii'));
    cipher2.start({ iv: uint8ArrayToString(iv, 'ascii') });
    return {
        update: (data) => {
            cipher2.update(forge.util.createBuffer(uint8ArrayToString(data, 'ascii')));
            return uint8ArrayFromString(cipher2.output.getBytes(), 'ascii');
        }
    };
}
//# sourceMappingURL=ciphers-browser.js.map