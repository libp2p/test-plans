import { Uint8ArrayList } from 'uint8arraylist';
import type { IHandshake } from '../@types/handshake-interface.js';
import type { MetricsRegistry } from '../metrics.js';
import type { Transform } from 'it-stream-types';
export declare function encryptStream(handshake: IHandshake, metrics?: MetricsRegistry): Transform<AsyncGenerator<Uint8Array | Uint8ArrayList>>;
export declare function decryptStream(handshake: IHandshake, metrics?: MetricsRegistry): Transform<AsyncGenerator<Uint8ArrayList>, AsyncGenerator<Uint8Array | Uint8ArrayList>>;
//# sourceMappingURL=streaming.d.ts.map