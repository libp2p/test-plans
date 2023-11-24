import type { Libp2pOptions } from '../../src/index.js';
import type { KadDHT } from '@libp2p/kad-dht';
export declare function createRoutingOptions(...overrides: Libp2pOptions[]): Libp2pOptions<{
    dht: KadDHT;
}>;
//# sourceMappingURL=utils.d.ts.map