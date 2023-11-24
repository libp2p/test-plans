import type { Libp2pInit } from './index.js';
import type { ServiceMap, RecursivePartial } from '@libp2p/interface';
export declare function validateConfig<T extends ServiceMap = Record<string, unknown>>(opts: RecursivePartial<Libp2pInit<T>>): Libp2pInit<T>;
//# sourceMappingURL=config.d.ts.map