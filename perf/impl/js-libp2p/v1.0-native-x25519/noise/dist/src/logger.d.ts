import { type Logger } from '@libp2p/logger';
import type { NoiseSession } from './@types/handshake.js';
import type { KeyPair } from './@types/libp2p.js';
declare const log: Logger;
export { log as logger };
export declare function logLocalStaticKeys(s: KeyPair): void;
export declare function logLocalEphemeralKeys(e: KeyPair | undefined): void;
export declare function logRemoteStaticKey(rs: Uint8Array): void;
export declare function logRemoteEphemeralKey(re: Uint8Array): void;
export declare function logCipherState(session: NoiseSession): void;
//# sourceMappingURL=logger.d.ts.map