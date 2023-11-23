import type { bytes } from './@types/basic.js';
import type { MessageBuffer } from './@types/handshake.js';
import type { LengthDecoderFunction } from 'it-length-prefixed';
export declare const uint16BEEncode: {
    (value: number): Uint8Array;
    bytes: number;
};
export declare const uint16BEDecode: LengthDecoderFunction;
export declare function encode0(message: MessageBuffer): bytes;
export declare function encode1(message: MessageBuffer): bytes;
export declare function encode2(message: MessageBuffer): bytes;
export declare function decode0(input: bytes): MessageBuffer;
export declare function decode1(input: bytes): MessageBuffer;
export declare function decode2(input: bytes): MessageBuffer;
//# sourceMappingURL=encoder.d.ts.map