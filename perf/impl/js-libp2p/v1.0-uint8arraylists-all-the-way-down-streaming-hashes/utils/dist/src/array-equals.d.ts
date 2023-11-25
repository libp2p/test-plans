/**
 * @packageDocumentation
 *
 * Provides strategies ensure arrays are equivalent.
 *
 * @example
 *
 * ```typescript
 * import { arrayEquals } from '@libp2p/utils/array-equals'
 * import { multiaddr } from '@multformats/multiaddr'
 *
 * const ma1 = multiaddr('/ip4/127.0.0.1/tcp/9000'),
 * const ma2 = multiaddr('/ip4/82.41.53.1/tcp/9000')
 *
 * console.info(arrayEquals([ma1], [ma1])) // true
 * console.info(arrayEquals([ma1], [ma2])) // false
 * ```
 */
/**
 * Verify if two arrays of non primitive types with the "equals" function are equal.
 * Compatible with multiaddr, peer-id and others.
 */
export declare function arrayEquals(a: any[], b: any[]): boolean;
//# sourceMappingURL=array-equals.d.ts.map