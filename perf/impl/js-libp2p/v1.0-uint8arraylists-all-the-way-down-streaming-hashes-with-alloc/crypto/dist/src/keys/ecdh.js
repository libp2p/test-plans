import crypto from 'crypto';
import { CodeError } from '@libp2p/interface/errors';
const curves = {
    'P-256': 'prime256v1',
    'P-384': 'secp384r1',
    'P-521': 'secp521r1'
};
const curveTypes = Object.keys(curves);
const names = curveTypes.join(' / ');
/**
 * Generates an ephemeral public key and returns a function that will compute the shared secret key.
 *
 * Focuses only on ECDH now, but can be made more general in the future.
 */
export async function generateEphmeralKeyPair(curve) {
    if (curve !== 'P-256' && curve !== 'P-384' && curve !== 'P-521') {
        throw new CodeError(`Unknown curve: ${curve}. Must be ${names}`, 'ERR_INVALID_CURVE');
    }
    const ecdh = crypto.createECDH(curves[curve]);
    ecdh.generateKeys();
    return {
        key: ecdh.getPublicKey(),
        async genSharedKey(theirPub, forcePrivate) {
            if (forcePrivate != null) {
                ecdh.setPrivateKey(forcePrivate.private);
            }
            return ecdh.computeSecret(theirPub);
        }
    };
}
//# sourceMappingURL=ecdh.js.map