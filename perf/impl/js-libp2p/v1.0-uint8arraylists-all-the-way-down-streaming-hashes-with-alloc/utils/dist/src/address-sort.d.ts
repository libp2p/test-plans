/**
 * @packageDocumentation
 *
 * Provides strategies to sort a list of multiaddrs.
 *
 * @example
 *
 * ```typescript
 * import { publicAddressesFirst } from '@libp2p/utils/address-sort'
 * import { multiaddr } from '@multformats/multiaddr'
 *
 *
 * const addresses = [
 *   multiaddr('/ip4/127.0.0.1/tcp/9000'),
 *   multiaddr('/ip4/82.41.53.1/tcp/9000')
 * ].sort(publicAddressesFirst)
 *
 * console.info(addresses)
 * // ['/ip4/82.41.53.1/tcp/9000', '/ip4/127.0.0.1/tcp/9000']
 * ```
 */
import type { Address } from '@libp2p/interface/peer-store';
/**
 * Compare function for array.sort() that moves public addresses to the start
 * of the array.
 */
export declare function publicAddressesFirst(a: Address, b: Address): -1 | 0 | 1;
/**
 * Compare function for array.sort() that moves certified addresses to the start
 * of the array.
 */
export declare function certifiedAddressesFirst(a: Address, b: Address): -1 | 0 | 1;
/**
 * Compare function for array.sort() that moves circuit relay addresses to the
 * start of the array.
 */
export declare function circuitRelayAddressesLast(a: Address, b: Address): -1 | 0 | 1;
export declare function defaultAddressSort(a: Address, b: Address): -1 | 0 | 1;
//# sourceMappingURL=address-sort.d.ts.map