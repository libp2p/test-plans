import { CodeError } from '@libp2p/interface/errors';
import {} from 'uint8arraylist';
import { fromString as uint8ArrayFromString } from 'uint8arrays/from-string';
import { toString as uint8ArrayToString } from 'uint8arrays/to-string';
const NewLine = uint8ArrayFromString('\n');
/**
 * `write` encodes and writes a single buffer
 */
export async function write(writer, buffer, options) {
    await writer.write(buffer, options);
}
/**
 * `writeAll` behaves like `write`, except it encodes an array of items as a single write
 */
export async function writeAll(writer, buffers, options) {
    await writer.writeV(buffers, options);
}
/**
 * Read a length-prefixed buffer from the passed stream, stripping the final newline character
 */
export async function read(reader, options) {
    const buf = await reader.read(options);
    if (buf.byteLength === 0 || buf.get(buf.byteLength - 1) !== NewLine[0]) {
        options?.log.error('Invalid mss message - missing newline', buf);
        throw new CodeError('missing newline', 'ERR_INVALID_MULTISTREAM_SELECT_MESSAGE');
    }
    return buf.sublist(0, -1); // Remove newline
}
/**
 * Read a length-prefixed string from the passed stream, stripping the final newline character
 */
export async function readString(reader, options) {
    const buf = await read(reader, options);
    return uint8ArrayToString(buf.subarray());
}
//# sourceMappingURL=multistream.js.map