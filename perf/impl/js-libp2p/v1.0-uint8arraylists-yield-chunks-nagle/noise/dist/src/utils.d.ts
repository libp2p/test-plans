import { type NoiseExtensions, NoiseHandshakePayload } from './proto/payload.js';
import type { bytes } from './@types/basic.js';
import type { PeerId } from '@libp2p/interface/peer-id';
export declare function getPayload(localPeer: PeerId, staticPublicKey: bytes, extensions?: NoiseExtensions): Promise<bytes>;
export declare function createHandshakePayload(libp2pPublicKey: Uint8Array, signedPayload: Uint8Array, extensions?: NoiseExtensions): bytes;
export declare function signPayload(peerId: PeerId, payload: bytes): Promise<bytes>;
export declare function getPeerIdFromPayload(payload: NoiseHandshakePayload): Promise<PeerId>;
export declare function decodePayload(payload: bytes | Uint8Array): NoiseHandshakePayload;
export declare function getHandshakePayload(publicKey: bytes): bytes;
/**
 * Verifies signed payload, throws on any irregularities.
 *
 * @param {bytes} noiseStaticKey - owner's noise static key
 * @param {bytes} payload - decoded payload
 * @param {PeerId} remotePeer - owner's libp2p peer ID
 * @returns {Promise<PeerId>} - peer ID of payload owner
 */
export declare function verifySignedPayload(noiseStaticKey: bytes, payload: NoiseHandshakePayload, remotePeer: PeerId): Promise<PeerId>;
export declare function isValidPublicKey(pk: bytes): boolean;
//# sourceMappingURL=utils.d.ts.map