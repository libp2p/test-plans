import { XX } from './handshakes/xx.js';
import type { bytes, bytes32 } from './@types/basic.js';
import type { IHandshake } from './@types/handshake-interface.js';
import type { NoiseSession } from './@types/handshake.js';
import type { KeyPair } from './@types/libp2p.js';
import type { ICryptoInterface } from './crypto.js';
import type { NoiseComponents } from './index.js';
import type { NoiseExtensions } from './proto/payload.js';
import type { PeerId } from '@libp2p/interface';
import type { LengthPrefixedStream } from 'it-length-prefixed-stream';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare class XXHandshake implements IHandshake {
    isInitiator: boolean;
    session: NoiseSession;
    remotePeer: PeerId;
    remoteExtensions: NoiseExtensions;
    protected payload: bytes;
    protected connection: LengthPrefixedStream;
    protected xx: XX;
    protected staticKeypair: KeyPair;
    private readonly prologue;
    private readonly log;
    constructor(components: NoiseComponents, isInitiator: boolean, payload: bytes, prologue: bytes32, crypto: ICryptoInterface, staticKeypair: KeyPair, connection: LengthPrefixedStream, remotePeer?: PeerId, handshake?: XX);
    propose(): Promise<void>;
    exchange(): Promise<void>;
    finish(): Promise<void>;
    encrypt(plaintext: Uint8Array | Uint8ArrayList, session: NoiseSession): Uint8Array | Uint8ArrayList;
    decrypt(ciphertext: Uint8Array | Uint8ArrayList, session: NoiseSession, dst?: Uint8Array): {
        plaintext: Uint8Array | Uint8ArrayList;
        valid: boolean;
    };
    getRemoteStaticKey(): Uint8Array | Uint8ArrayList;
    private getCS;
    protected setRemoteNoiseExtension(e: NoiseExtensions | null | undefined): void;
}
//# sourceMappingURL=handshake-xx.d.ts.map