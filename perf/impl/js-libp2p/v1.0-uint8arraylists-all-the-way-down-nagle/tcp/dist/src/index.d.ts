/**
 * @packageDocumentation
 *
 * A [libp2p transport](https://docs.libp2p.io/concepts/transports/overview/) based on the TCP networking stack.
 *
 * @example
 *
 * ```js
 * import { tcp } from '@libp2p/tcp'
 * import { multiaddr } from '@multiformats/multiaddr'
 * import { pipe } from 'it-pipe'
 * import all from 'it-all'
 *
 * // A simple upgrader that just returns the MultiaddrConnection
 * const upgrader = {
 *   upgradeInbound: async maConn => maConn,
 *   upgradeOutbound: async maConn => maConn
 * }
 *
 * const transport = tcp()()
 *
 * const listener = transport.createListener({
 *   upgrader,
 *   handler: (socket) => {
 *     console.this.log('new connection opened')
 *     pipe(
 *       ['hello', ' ', 'World!'],
 *       socket
 *     )
 *   }
 * })
 *
 * const addr = multiaddr('/ip4/127.0.0.1/tcp/9090')
 * await listener.listen(addr)
 * console.this.log('listening')
 *
 * const socket = await transport.dial(addr, { upgrader })
 * const values = await pipe(
 *   socket,
 *   all
 * )
 * console.this.log(`Value: ${values.toString()}`)
 *
 * // Close connection after reading
 * await listener.close()
 * ```
 *
 * Outputs:
 *
 * ```sh
 * listening
 * new connection opened
 * Value: hello World!
 * ```
 */
import { type CreateListenerOptions, type DialOptions, type Transport } from '@libp2p/interface/transport';
import { type CloseServerOnMaxConnectionsOpts } from './listener.js';
import type { ComponentLogger } from '@libp2p/interface';
import type { CounterGroup, Metrics } from '@libp2p/interface/metrics';
import type { AbortOptions } from '@multiformats/multiaddr';
export interface TCPOptions {
    /**
     * An optional number in ms that is used as an inactivity timeout after which the socket will be closed
     */
    inboundSocketInactivityTimeout?: number;
    /**
     * An optional number in ms that is used as an inactivity timeout after which the socket will be closed
     */
    outboundSocketInactivityTimeout?: number;
    /**
     * When closing a socket, wait this long for it to close gracefully before it is closed more forcibly
     */
    socketCloseTimeout?: number;
    /**
     * Set this property to reject connections when the server's connection count gets high.
     * https://nodejs.org/api/net.html#servermaxconnections
     */
    maxConnections?: number;
    /**
     * Parameter to specify the maximum length of the queue of pending connections
     * https://nodejs.org/dist/latest-v18.x/docs/api/net.html#serverlisten
     */
    backlog?: number;
    /**
     * Close server (stop listening for new connections) if connections exceed a limit.
     * Open server (start listening for new connections) if connections fall below a limit.
     */
    closeServerOnMaxConnections?: CloseServerOnMaxConnectionsOpts;
    /**
     * Options passed to `net.connect` for every opened TCP socket
     */
    dialOpts?: TCPSocketOptions;
    /**
     * Options passed to every `net.createServer` for every TCP server
     */
    listenOpts?: TCPSocketOptions;
}
/**
 * Expose a subset of net.connect options
 */
export interface TCPSocketOptions extends AbortOptions {
    /**
     * @see https://nodejs.org/dist/latest-v18.x/docs/api/net.html#serverlisten
     */
    noDelay?: boolean;
    /**
     * @see https://nodejs.org/dist/latest-v18.x/docs/api/net.html#serverlisten
     */
    keepAlive?: boolean;
    /**
     * @see https://nodejs.org/dist/latest-v18.x/docs/api/net.html#serverlisten
     */
    keepAliveInitialDelay?: number;
    /**
     * @see https://nodejs.org/dist/latest-v18.x/docs/api/net.html#new-netsocketoptions
     */
    allowHalfOpen?: boolean;
}
export interface TCPDialOptions extends DialOptions, TCPSocketOptions {
}
export interface TCPCreateListenerOptions extends CreateListenerOptions, TCPSocketOptions {
}
export interface TCPComponents {
    metrics?: Metrics;
    logger: ComponentLogger;
}
export interface TCPMetrics {
    dialerEvents: CounterGroup;
}
export declare function tcp(init?: TCPOptions): (components: TCPComponents) => Transport;
//# sourceMappingURL=index.d.ts.map