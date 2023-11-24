import { Uint8ArrayList } from 'uint8arraylist';
import type { Source, Duplex } from 'it-stream-types';
/**
 * A pair of streams where one drains from the other
 */
export declare function pair(): Duplex<AsyncGenerator<Uint8ArrayList>, Source<Uint8ArrayList | Uint8Array>, Promise<void>>;
//# sourceMappingURL=pair.d.ts.map