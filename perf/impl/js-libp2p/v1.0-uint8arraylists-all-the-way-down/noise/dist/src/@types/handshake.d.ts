import type { bytes, bytes32, uint64 } from './basic.js';
import type { KeyPair } from './libp2p.js';
import type { Nonce } from '../nonce.js';
export type Hkdf = [bytes, bytes, bytes];
export interface MessageBuffer {
    ne: bytes32;
    ns: bytes;
    ciphertext: bytes;
}
export interface CipherState {
    k: bytes32;
    n: Nonce;
}
export interface SymmetricState {
    cs: CipherState;
    ck: bytes32;
    h: bytes32;
}
export interface HandshakeState {
    ss: SymmetricState;
    s: KeyPair;
    e?: KeyPair;
    rs: bytes32;
    re: bytes32;
    psk: bytes32;
}
export interface NoiseSession {
    hs: HandshakeState;
    h?: bytes32;
    cs1?: CipherState;
    cs2?: CipherState;
    mc: uint64;
    i: boolean;
}
export interface INoisePayload {
    identityKey: bytes;
    identitySig: bytes;
    data: bytes;
}
//# sourceMappingURL=handshake.d.ts.map