/// <reference types="node" />
import { Duplex as DuplexStream } from 'node:stream';
import type { PeerId, Logger } from '@libp2p/interface';
import type { Duplex } from 'it-stream-types';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare function verifyPeerCertificate(rawCertificate: Uint8Array, expectedPeerId?: PeerId, log?: Logger): Promise<PeerId>;
export declare function generateCertificate(peerId: PeerId): Promise<{
    cert: string;
    key: string;
}>;
/**
 * @see https://github.com/libp2p/specs/blob/master/tls/tls.md#libp2p-public-key-extension
 */
export declare function encodeSignatureData(certPublicKey: ArrayBuffer): Uint8Array;
export declare function itToStream(conn: Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>>): DuplexStream;
export declare function streamToIt(stream: DuplexStream): Duplex<AsyncGenerator<Uint8Array | Uint8ArrayList>>;
//# sourceMappingURL=utils.d.ts.map