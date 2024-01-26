/**
 * @packageDocumentation
 *
 * Implements the spec at https://github.com/libp2p/specs/blob/master/tls/tls.md
 *
 * @example
 *
 * ```typescript
 * import { createLibp2p } from 'libp2p'
 * import { tls } from '@libp2p/tls'
 *
 * const node = await createLibp2p({
 *   // ...other options
 *   connectionEncryption: [
 *     tls()
 *   ]
 * })
 * ```
 */
import type { ComponentLogger, ConnectionEncrypter } from '@libp2p/interface';
export interface TLSComponents {
    logger: ComponentLogger;
}
export interface TLSInit {
    /**
     * The peer id exchange must complete within this many milliseconds
     * (default: 1000)
     */
    timeout?: number;
}
export declare function tls(init?: TLSInit): (components: TLSComponents) => ConnectionEncrypter;
//# sourceMappingURL=index.d.ts.map