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
export const peerRouting = Symbol.for('@libp2p/peer-routing');
//# sourceMappingURL=index.js.map