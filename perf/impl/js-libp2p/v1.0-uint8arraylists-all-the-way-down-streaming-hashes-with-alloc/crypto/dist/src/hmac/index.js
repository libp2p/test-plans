/**
 * @packageDocumentation
 *
 * Exposes an interface to the Keyed-Hash Message Authentication Code (HMAC) as defined in U.S. Federal Information Processing Standards Publication 198. An HMAC is a cryptographic hash that uses a key to sign a message. The receiver verifies the hash by recomputing it using the same key.
 *
 * @example
 *
 * ```js
 * import { create } from '@libp2p/hmac'
 *
 * const hash = 'SHA1' // 'SHA256' || 'SHA512'
 * const hmac = await crypto.hmac.create(hash, uint8ArrayFromString('secret'))
 * const sig = await hmac.digest(uint8ArrayFromString('hello world'))
 * console.log(sig)
 * ```
 */
import crypto from 'crypto';
import lengths from './lengths.js';
export async function create(hash, secret) {
    const res = {
        async digest(data) {
            const hmac = crypto.createHmac(hash.toLowerCase(), secret);
            hmac.update(data);
            return hmac.digest();
        },
        length: lengths[hash]
    };
    return res;
}
//# sourceMappingURL=index.js.map