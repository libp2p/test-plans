import type { NoiseSession } from './@types/handshake.js';
import type { KeyPair } from './@types/libp2p.js';
import type { Logger } from '@libp2p/interface';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare function logLocalStaticKeys(s: KeyPair, keyLogger: Logger): void;
export declare function logLocalEphemeralKeys(e: KeyPair | undefined, keyLogger: Logger): void;
export declare function logRemoteStaticKey(rs: Uint8Array | Uint8ArrayList, keyLogger: Logger): void;
export declare function logRemoteEphemeralKey(re: Uint8Array | Uint8ArrayList, keyLogger: Logger): void;
export declare function logCipherState(session: NoiseSession, keyLogger: Logger): void;
//# sourceMappingURL=logger.d.ts.map