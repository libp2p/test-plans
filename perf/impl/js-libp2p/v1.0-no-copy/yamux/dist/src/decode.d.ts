import { Uint8ArrayList } from 'uint8arraylist';
import { type FrameHeader } from './frame.js';
import type { Source } from 'it-stream-types';
/**
 * Decode a header from the front of a buffer
 *
 * @param data - Assumed to have enough bytes for a header
 */
export declare function decodeHeader(data: Uint8Array): FrameHeader;
/**
 * Decodes yamux frames from a source
 */
export declare class Decoder {
    private readonly source;
    /** Buffer for in-progress frames */
    private readonly buffer;
    /** Used to sanity check against decoding while in an inconsistent state */
    private frameInProgress;
    constructor(source: Source<Uint8Array | Uint8ArrayList>);
    /**
     * Emits frames from the decoder source.
     *
     * Note: If `readData` is emitted, it _must_ be called before the next iteration
     * Otherwise an error is thrown
     */
    emitFrames(): AsyncGenerator<{
        header: FrameHeader;
        readData?: () => Promise<Uint8ArrayList>;
    }>;
    private readHeader;
    private readBytes;
}
/**
 * Strip the `return` method from a `Source`
 */
export declare function returnlessSource<T>(source: Source<T>): Source<T>;
//# sourceMappingURL=decode.d.ts.map