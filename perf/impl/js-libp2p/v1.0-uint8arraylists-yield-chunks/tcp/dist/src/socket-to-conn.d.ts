import type { ComponentLogger } from '@libp2p/interface';
import type { MultiaddrConnection } from '@libp2p/interface/connection';
import type { CounterGroup } from '@libp2p/interface/metrics';
import type { Multiaddr } from '@multiformats/multiaddr';
import type { Socket } from 'net';
interface ToConnectionOptions {
    listeningAddr?: Multiaddr;
    remoteAddr?: Multiaddr;
    localAddr?: Multiaddr;
    socketInactivityTimeout?: number;
    socketCloseTimeout?: number;
    metrics?: CounterGroup;
    metricPrefix?: string;
    logger: ComponentLogger;
}
/**
 * Convert a socket into a MultiaddrConnection
 * https://github.com/libp2p/interface-transport#multiaddrconnection
 */
export declare const toMultiaddrConnection: (socket: Socket, options: ToConnectionOptions) => MultiaddrConnection;
export {};
//# sourceMappingURL=socket-to-conn.d.ts.map