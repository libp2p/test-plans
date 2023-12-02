import type { NoiseInit } from './noise.js';
import type { NoiseExtensions } from './proto/payload.js';
import type { ComponentLogger, ConnectionEncrypter, Metrics } from '@libp2p/interface';
export type { ICryptoInterface } from './crypto.js';
export { pureJsCrypto } from './crypto/js.js';
export interface NoiseComponents {
    logger: ComponentLogger;
    metrics?: Metrics;
}
export declare function noise(init?: NoiseInit): (components: NoiseComponents) => ConnectionEncrypter<NoiseExtensions>;
//# sourceMappingURL=index.d.ts.map