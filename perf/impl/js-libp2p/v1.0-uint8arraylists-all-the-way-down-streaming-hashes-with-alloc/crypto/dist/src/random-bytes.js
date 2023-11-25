import { CodeError } from '@libp2p/interface/errors';
import { randomBytes as randB } from '@noble/hashes/utils';
/**
 * Generates a Uint8Array with length `number` populated by random bytes
 */
export default function randomBytes(length) {
    if (isNaN(length) || length <= 0) {
        throw new CodeError('random bytes length must be a Number bigger than 0', 'ERR_INVALID_LENGTH');
    }
    return randB(length);
}
//# sourceMappingURL=random-bytes.js.map