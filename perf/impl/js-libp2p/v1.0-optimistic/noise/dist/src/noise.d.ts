import type { bytes } from './@types/basic.js';
import type { INoiseConnection } from './@types/libp2p.js';
import type { ICryptoInterface } from './crypto.js';
import type { NoiseExtensions } from './proto/payload.js';
import type { SecuredConnection } from '@libp2p/interface/connection-encrypter';
import type { Metrics } from '@libp2p/interface/metrics';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { Duplex } from 'it-stream-types';
export interface NoiseInit {
    /**
     * x25519 private key, reuse for faster handshakes
     */
    staticNoiseKey?: bytes;
    extensions?: NoiseExtensions;
    crypto?: ICryptoInterface;
    prologueBytes?: Uint8Array;
    metrics?: Metrics;
}
export declare class Noise implements INoiseConnection {
    protocol: string;
    crypto: ICryptoInterface;
    private readonly prologue;
    private readonly staticKeys;
    private readonly extensions?;
    private readonly metrics?;
    constructor(init?: NoiseInit);
    /**
     * Encrypt outgoing data to the remote party (handshake as initiator)
     *
     * @param {PeerId} localPeer - PeerId of the receiving peer
     * @param {Duplex<AsyncGenerator<Uint8Array>, AsyncIterable<Uint8Array>, Promise<void>>} connection - streaming iterable duplex that will be encrypted
     * @param {PeerId} remotePeer - PeerId of the remote peer. Used to validate the integrity of the remote peer.
     * @returns {Promise<SecuredConnection>}
     */
    secureOutbound(localPeer: PeerId, connection: Duplex<AsyncGenerator<Uint8Array>, AsyncIterable<Uint8Array>, Promise<void>>, remotePeer?: PeerId): Promise<SecuredConnection<NoiseExtensions>>;
    /**
     * Decrypt incoming data (handshake as responder).
     *
     * @param {PeerId} localPeer - PeerId of the receiving peer.
     * @param {Duplex<AsyncGenerator<Uint8Array>, AsyncIterable<Uint8Array>, Promise<void>>} connection - streaming iterable duplex that will be encryption.
     * @param {PeerId} remotePeer - optional PeerId of the initiating peer, if known. This may only exist during transport upgrades.
     * @returns {Promise<SecuredConnection>}
     */
    secureInbound(localPeer: PeerId, connection: Duplex<AsyncGenerator<Uint8Array>, AsyncIterable<Uint8Array>, Promise<void>>, remotePeer?: PeerId): Promise<SecuredConnection<NoiseExtensions>>;
    /**
     * If Noise pipes supported, tries IK handshake first with XX as fallback if it fails.
     * If noise pipes disabled or remote peer static key is unknown, use XX.
     *
     * @param {HandshakeParams} params
     */
    private performHandshake;
    private performXXHandshake;
    private createSecureConnection;
}
//# sourceMappingURL=noise.d.ts.map