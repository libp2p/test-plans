import type { TypedEventTarget } from '../events.js';
import type { PeerInfo } from '../peer-info/index.js';
/**
 * Any object that implements this Symbol as a property should return a
 * PeerDiscovery instance as the property value, similar to how
 * `Symbol.Iterable` can be used to return an `Iterable` from an `Iterator`.
 *
 * @example
 *
 * ```js
 * import { peerDiscovery, PeerDiscovery } from '@libp2p/peer-discovery'
 *
 * class MyPeerDiscoverer implements PeerDiscovery {
 *   get [peerDiscovery] () {
 *     return this
 *   }
 *
 *   // ...other methods
 * }
 * ```
 */
export declare const peerDiscovery: unique symbol;
export interface PeerDiscoveryEvents {
    'peer': CustomEvent<PeerInfo>;
}
export interface PeerDiscovery extends TypedEventTarget<PeerDiscoveryEvents> {
}
//# sourceMappingURL=index.d.ts.map