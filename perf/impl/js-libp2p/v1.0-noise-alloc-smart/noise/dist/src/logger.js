import { toString as uint8ArrayToString } from 'uint8arrays/to-string';
import { DUMP_SESSION_KEYS } from './constants.js';
export function logLocalStaticKeys(s, keyLogger) {
    if (!keyLogger.enabled || !DUMP_SESSION_KEYS) {
        return;
    }
    keyLogger(`LOCAL_STATIC_PUBLIC_KEY ${uint8ArrayToString(s.publicKey, 'hex')}`);
    keyLogger(`LOCAL_STATIC_PRIVATE_KEY ${uint8ArrayToString(s.privateKey, 'hex')}`);
}
export function logLocalEphemeralKeys(e, keyLogger) {
    if (!keyLogger.enabled || !DUMP_SESSION_KEYS) {
        return;
    }
    if (e) {
        keyLogger(`LOCAL_PUBLIC_EPHEMERAL_KEY ${uint8ArrayToString(e.publicKey, 'hex')}`);
        keyLogger(`LOCAL_PRIVATE_EPHEMERAL_KEY ${uint8ArrayToString(e.privateKey, 'hex')}`);
    }
    else {
        keyLogger('Missing local ephemeral keys.');
    }
}
export function logRemoteStaticKey(rs, keyLogger) {
    if (!keyLogger.enabled || !DUMP_SESSION_KEYS) {
        return;
    }
    keyLogger(`REMOTE_STATIC_PUBLIC_KEY ${uint8ArrayToString(rs.subarray(), 'hex')}`);
}
export function logRemoteEphemeralKey(re, keyLogger) {
    if (!keyLogger.enabled || !DUMP_SESSION_KEYS) {
        return;
    }
    keyLogger(`REMOTE_EPHEMERAL_PUBLIC_KEY ${uint8ArrayToString(re.subarray(), 'hex')}`);
}
export function logCipherState(session, keyLogger) {
    if (!keyLogger.enabled || !DUMP_SESSION_KEYS) {
        return;
    }
    if (session.cs1 && session.cs2) {
        keyLogger(`CIPHER_STATE_1 ${session.cs1.n.getUint64()} ${uint8ArrayToString(session.cs1.k, 'hex')}`);
        keyLogger(`CIPHER_STATE_2 ${session.cs2.n.getUint64()} ${uint8ArrayToString(session.cs2.k, 'hex')}`);
    }
    else {
        keyLogger('Missing cipher state.');
    }
}
//# sourceMappingURL=logger.js.map