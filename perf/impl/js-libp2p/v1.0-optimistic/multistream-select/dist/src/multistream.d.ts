import { type Uint8ArrayList } from 'uint8arraylist';
import type { MultistreamSelectInit } from '.';
import type { AbortOptions, LoggerOptions } from '@libp2p/interface';
import type { LengthPrefixedStream } from 'it-length-prefixed-stream';
import type { Duplex, Source } from 'it-stream-types';
/**
 * `write` encodes and writes a single buffer
 */
export declare function write(writer: LengthPrefixedStream<Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>, Source<Uint8Array>>>, buffer: Uint8Array | Uint8ArrayList, options?: MultistreamSelectInit): Promise<void>;
/**
 * `writeAll` behaves like `write`, except it encodes an array of items as a single write
 */
export declare function writeAll(writer: LengthPrefixedStream<Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>, Source<Uint8Array>>>, buffers: Uint8Array[], options?: MultistreamSelectInit): Promise<void>;
/**
 * Read a length-prefixed buffer from the passed stream, stripping the final newline character
 */
export declare function read(reader: LengthPrefixedStream<Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>, Source<Uint8Array>>>, options?: AbortOptions & LoggerOptions): Promise<Uint8ArrayList>;
/**
 * Read a length-prefixed string from the passed stream, stripping the final newline character
 */
export declare function readString(reader: LengthPrefixedStream<Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>, Source<Uint8Array>>>, options?: AbortOptions & LoggerOptions): Promise<string>;
//# sourceMappingURL=multistream.d.ts.map