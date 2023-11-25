import type { NoiseInit } from './noise.js';
import type { NoiseExtensions } from './proto/payload.js';
import type { ConnectionEncrypter } from '@libp2p/interface/connection-encrypter';
export type { ICryptoInterface } from './crypto.js';
export { pureJsCrypto } from './crypto/js.js';
export declare function noise(init?: NoiseInit): () => ConnectionEncrypter<NoiseExtensions>;
//# sourceMappingURL=index.d.ts.map