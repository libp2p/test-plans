import { type Uint8ArrayList } from 'uint8arraylist';
import { type NoiseExtensions, NoiseHandshakePayload } from './proto/payload.js';
import type { bytes } from './@types/basic.js';
import type { PeerId } from '@libp2p/interface';
export declare function getPayload(localPeer: PeerId, staticPublicKey: bytes, extensions?: NoiseExtensions): Promise<bytes>;
export declare function createHandshakePayload(libp2pPublicKey: Uint8Array, signedPayload: Uint8Array, extensions?: NoiseExtensions): bytes;
export declare function signPayload(peerId: PeerId, payload: Uint8Array | Uint8ArrayList): Promise<bytes>;
export declare function getPeerIdFromPayload(payload: NoiseHandshakePayload): Promise<PeerId>;
export declare function decodePayload(payload: Uint8Array | Uint8ArrayList): NoiseHandshakePayload;
export declare function getHandshakePayload(publicKey: Uint8Array | Uint8ArrayList): Uint8Array | Uint8ArrayList;
/**
 * Verifies signed payload, throws on any irregularities.
 *
 * @param {bytes} noiseStaticKey - owner's noise static key
 * @param {bytes} payload - decoded payload
 * @param {PeerId} remotePeer - owner's libp2p peer ID
 * @returns {Promise<PeerId>} - peer ID of payload owner
 */
export declare function verifySignedPayload(noiseStaticKey: Uint8Array | Uint8ArrayList, payload: NoiseHandshakePayload, remotePeer: PeerId): Promise<PeerId>;
export declare function isValidPublicKey(pk: Uint8Array | Uint8ArrayList): boolean;
//# sourceMappingURL=utils.d.ts.map