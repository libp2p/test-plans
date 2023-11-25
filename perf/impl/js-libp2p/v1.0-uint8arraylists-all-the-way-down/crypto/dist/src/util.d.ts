import 'node-forge/lib/util.js';
import 'node-forge/lib/jsbn.js';
import forge from 'node-forge/lib/forge.js';
export declare function bigIntegerToUintBase64url(num: {
    abs(): any;
}, len?: number): string;
export declare function base64urlToBigInteger(str: string): typeof forge.jsbn.BigInteger;
export declare function base64urlToBuffer(str: string, len?: number): Uint8Array;
//# sourceMappingURL=util.d.ts.map