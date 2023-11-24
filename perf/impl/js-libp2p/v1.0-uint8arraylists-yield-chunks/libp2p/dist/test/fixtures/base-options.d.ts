import type { Libp2pOptions } from '../../src';
import type { ServiceMap } from '@libp2p/interface';
export declare function createBaseOptions<T extends ServiceMap = Record<string, unknown>>(...overrides: Array<Libp2pOptions<T>>): Libp2pOptions<T>;
//# sourceMappingURL=base-options.d.ts.map