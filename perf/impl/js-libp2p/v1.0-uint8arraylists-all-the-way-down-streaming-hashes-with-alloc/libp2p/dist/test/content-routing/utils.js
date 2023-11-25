import { kadDHT } from '@libp2p/kad-dht';
import { createBaseOptions } from '../fixtures/base-options.js';
export function createRoutingOptions(...overrides) {
    return createBaseOptions({
        services: {
            dht: kadDHT()
        }
    }, ...overrides);
}
//# sourceMappingURL=utils.js.map