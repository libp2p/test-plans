import { alloc as uint8ArrayAlloc, allocUnsafe as uint8ArrayAllocUnsafe } from 'uint8arrays/alloc';
import { concat as uint8ArrayConcat } from 'uint8arrays/concat';
export const uint16BEEncode = (value) => {
    const target = uint8ArrayAllocUnsafe(2);
    new DataView(target.buffer, target.byteOffset, target.byteLength).setUint16(0, value, false);
    return target;
};
uint16BEEncode.bytes = 2;
export const uint16BEDecode = (data) => {
    if (data.length < 2)
        throw RangeError('Could not decode int16BE');
    if (data instanceof Uint8Array) {
        return new DataView(data.buffer, data.byteOffset, data.byteLength).getUint16(0, false);
    }
    return data.getUint16(0);
};
uint16BEDecode.bytes = 2;
// Note: IK and XX encoder usage is opposite (XX uses in stages encode0 where IK uses encode1)
export function encode0(message) {
    return uint8ArrayConcat([message.ne, message.ciphertext], message.ne.length + message.ciphertext.length);
}
export function encode1(message) {
    return uint8ArrayConcat([message.ne, message.ns, message.ciphertext], message.ne.length + message.ns.length + message.ciphertext.length);
}
export function encode2(message) {
    return uint8ArrayConcat([message.ns, message.ciphertext], message.ns.length + message.ciphertext.length);
}
export function decode0(input) {
    if (input.length < 32) {
        throw new Error('Cannot decode stage 0 MessageBuffer: length less than 32 bytes.');
    }
    return {
        ne: input.subarray(0, 32),
        ciphertext: input.subarray(32, input.length),
        ns: uint8ArrayAlloc(0)
    };
}
export function decode1(input) {
    if (input.length < 80) {
        throw new Error('Cannot decode stage 1 MessageBuffer: length less than 80 bytes.');
    }
    return {
        ne: input.subarray(0, 32),
        ns: input.subarray(32, 80),
        ciphertext: input.subarray(80, input.length)
    };
}
export function decode2(input) {
    if (input.length < 48) {
        throw new Error('Cannot decode stage 2 MessageBuffer: length less than 48 bytes.');
    }
    return {
        ne: uint8ArrayAlloc(0),
        ns: input.subarray(0, 48),
        ciphertext: input.subarray(48, input.length)
    };
}
//# sourceMappingURL=encoder.js.map