import type { bytes, uint64 } from './@types/basic.js';
export declare const MIN_NONCE = 0;
export declare const MAX_NONCE = 4294967295;
/**
 * The nonce is an uint that's increased over time.
 * Maintaining different representations help improve performance.
 */
export declare class Nonce {
    private n;
    private readonly bytes;
    private readonly view;
    constructor(n?: number);
    increment(): void;
    getBytes(): bytes;
    getUint64(): uint64;
    assertValue(): void;
}
//# sourceMappingURL=nonce.d.ts.map