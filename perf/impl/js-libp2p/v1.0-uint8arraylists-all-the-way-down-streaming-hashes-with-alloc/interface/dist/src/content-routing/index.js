/**
 * Any object that implements this Symbol as a property should return a
 * ContentRouting instance as the property value, similar to how
 * `Symbol.Iterable` can be used to return an `Iterable` from an `Iterator`.
 *
 * @example
 *
 * ```js
 * import { contentRouting, ContentRouting } from '@libp2p/content-routing'
 *
 * class MyContentRouter implements ContentRouting {
 *   get [contentRouting] () {
 *     return this
 *   }
 *
 *   // ...other methods
 * }
 * ```
 */
export const contentRouting = Symbol.for('@libp2p/content-routing');
//# sourceMappingURL=index.js.map