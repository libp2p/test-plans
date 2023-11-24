import { type AbortOptions, type Multiaddr } from '@multiformats/multiaddr';
import { type ClearableSignal } from 'any-signal';
import type { LoggerOptions } from '@libp2p/interface';
/**
 * Resolve multiaddr recursively
 */
export declare function resolveMultiaddrs(ma: Multiaddr, options: AbortOptions & LoggerOptions): Promise<Multiaddr[]>;
export declare function combineSignals(...signals: Array<AbortSignal | undefined>): ClearableSignal;
//# sourceMappingURL=utils.d.ts.map