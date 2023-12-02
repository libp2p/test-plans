import type { bytes } from './@types/basic.js';
import type { INoiseConnection } from './@types/libp2p.js';
import type { ICryptoInterface } from './crypto.js';
import type { NoiseComponents } from './index.js';
import type { NoiseExtensions } from './proto/payload.js';
import type { MultiaddrConnection, SecuredConnection, PeerId } from '@libp2p/interface';
import type { Duplex } from 'it-stream-types';
import type { Uint8ArrayList } from 'uint8arraylist';
export interface NoiseInit {
    /**
     * x25519 private key, reuse for faster handshakes
     */
    staticNoiseKey?: bytes;
    extensions?: NoiseExtensions;
    crypto?: ICryptoInterface;
    prologueBytes?: Uint8Array;
}
export declare class Noise implements INoiseConnection {
    protocol: string;
    crypto: ICryptoInterface;
    private readonly prologue;
    private readonly staticKeys;
    private readonly extensions?;
    private readonly metrics?;
    private readonly components;
    constructor(components: NoiseComponents, init?: NoiseInit);
    /**
     * Encrypt outgoing data to the remote party (handshake as initiator)
     *
     * @param {PeerId} localPeer - PeerId of the receiving peer
     * @param {Stream} connection - streaming iterable duplex that will be encrypted
     * @param {PeerId} remotePeer - PeerId of the remote peer. Used to validate the integrity of the remote peer.
     * @returns {Promise<SecuredConnection<Stream, NoiseExtensions>>}
     */
    secureOutbound<Stream extends Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>> = MultiaddrConnection>(localPeer: PeerId, connection: Stream, remotePeer?: PeerId): Promise<SecuredConnection<Stream, NoiseExtensions>>;
    /**
     * Decrypt incoming data (handshake as responder).
     *
     * @param {PeerId} localPeer - PeerId of the receiving peer.
     * @param {Stream} connection - streaming iterable duplex that will be encrypted.
     * @param {PeerId} remotePeer - optional PeerId of the initiating peer, if known. This may only exist during transport upgrades.
     * @returns {Promise<SecuredConnection<Stream, NoiseExtensions>>}
     */
    secureInbound<Stream extends Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>> = MultiaddrConnection>(localPeer: PeerId, connection: Stream, remotePeer?: PeerId): Promise<SecuredConnection<Stream, NoiseExtensions>>;
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