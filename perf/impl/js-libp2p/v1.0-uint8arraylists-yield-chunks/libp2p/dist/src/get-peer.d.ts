import type { PeerId } from '@libp2p/interface/peer-id';
import type { Multiaddr } from '@multiformats/multiaddr';
export interface PeerAddress {
    peerId?: PeerId;
    multiaddrs: Multiaddr[];
}
/**
 * Extracts a PeerId and/or multiaddr from the passed PeerId or Multiaddr or an array of Multiaddrs
 */
export declare function getPeerAddress(peer: PeerId | Multiaddr | Multiaddr[]): PeerAddress;
//# sourceMappingURL=get-peer.d.ts.map