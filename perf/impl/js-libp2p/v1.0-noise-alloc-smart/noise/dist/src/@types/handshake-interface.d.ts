import type { NoiseSession } from './handshake.js';
import type { NoiseExtensions } from '../proto/payload.js';
import type { PeerId } from '@libp2p/interface';
import type { Uint8ArrayList } from 'uint8arraylist';
export interface IHandshake {
    session: NoiseSession;
    remotePeer: PeerId;
    remoteExtensions: NoiseExtensions;
    encrypt(plaintext: Uint8Array | Uint8ArrayList, session: NoiseSession): Uint8Array | Uint8ArrayList;
    decrypt(ciphertext: Uint8Array | Uint8ArrayList, session: NoiseSession, dst?: Uint8Array): {
        plaintext: Uint8Array | Uint8ArrayList;
        valid: boolean;
    };
}
//# sourceMappingURL=handshake-interface.d.ts.map