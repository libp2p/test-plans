import type { AbortOptions } from '../index.js';
import type { PeerId } from '../peer-id/index.js';
import type { PeerInfo } from '../peer-info/index.js';
/**
 * Any object that implements this Symbol as a property should return a
 * PeerRouting instance as the property value, similar to how
 * `Symbol.Iterable` can be used to return an `Iterable` from an `Iterator`.
 *
 * @example
 *
 * ```js
 * import { peerRouting, PeerRouting } from '@libp2p/peer-routing'
 *
 * class MyPeerRouter implements PeerRouting {
 *   get [peerRouting] () {
 *     return this
 *   }
 *
 *   // ...other methods
 * }
 * ```
 */
export declare const peerRouting: unique symbol;
export interface PeerRouting {
    /**
     * Searches the network for peer info corresponding to the passed peer id.
     *
     * @example
     *
     * ```js
     * // ...
     * const peer = await peerRouting.findPeer(peerId, options)
     * ```
     */
    findPeer(peerId: PeerId, options?: AbortOptions): Promise<PeerInfo>;
    /**
     * Search the network for peers that are closer to the passed key. Peer
     * info should be yielded in ever-increasing closeness to the key.
     *
     * @example
     *
     * ```js
     * // Iterate over the closest peers found for the given key
     * for await (const peer of peerRouting.getClosestPeers(key)) {
     *   console.log(peer.id, peer.multiaddrs)
     * }
     * ```
     */
    getClosestPeers(key: Uint8Array, options?: AbortOptions): AsyncIterable<PeerInfo>;
}
//# sourceMappingURL=index.d.ts.map