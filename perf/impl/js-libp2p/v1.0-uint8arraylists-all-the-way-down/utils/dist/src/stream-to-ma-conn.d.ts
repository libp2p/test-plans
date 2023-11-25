import type { ComponentLogger } from '@libp2p/interface';
import type { MultiaddrConnection, Stream } from '@libp2p/interface/connection';
import type { Multiaddr } from '@multiformats/multiaddr';
export interface StreamProperties {
    stream: Stream;
    remoteAddr: Multiaddr;
    localAddr: Multiaddr;
    logger: ComponentLogger;
}
/**
 * Convert a duplex iterable into a MultiaddrConnection.
 * https://github.com/libp2p/interface-transport#multiaddrconnection
 */
export declare function streamToMaConnection(props: StreamProperties): MultiaddrConnection;
//# sourceMappingURL=stream-to-ma-conn.d.ts.map