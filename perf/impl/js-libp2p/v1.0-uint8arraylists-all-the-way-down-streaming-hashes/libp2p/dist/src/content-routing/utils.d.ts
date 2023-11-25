import type { PeerInfo } from '@libp2p/interface/peer-info';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { Source } from 'it-stream-types';
/**
 * Store the multiaddrs from every peer in the passed peer store
 */
export declare function storeAddresses(source: Source<PeerInfo>, peerStore: PeerStore): AsyncIterable<PeerInfo>;
/**
 * Filter peers by unique peer id
 */
export declare function uniquePeers(source: Source<PeerInfo>): AsyncIterable<PeerInfo>;
/**
 * Require at least `min` peers to be yielded from `source`
 */
export declare function requirePeers(source: Source<PeerInfo>, min?: number): AsyncIterable<PeerInfo>;
//# sourceMappingURL=utils.d.ts.map