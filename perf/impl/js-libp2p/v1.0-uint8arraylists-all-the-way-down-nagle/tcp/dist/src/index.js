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
import net from 'net';
import { AbortError, CodeError } from '@libp2p/interface/errors';
import { symbol } from '@libp2p/interface/transport';
import * as mafmt from '@multiformats/mafmt';
import { CODE_CIRCUIT, CODE_P2P, CODE_UNIX } from './constants.js';
import { TCPListener } from './listener.js';
import { toMultiaddrConnection } from './socket-to-conn.js';
import { multiaddrToNetConfig } from './utils.js';
class TCP {
    opts;
    metrics;
    components;
    log;
    constructor(components, options = {}) {
        this.log = components.logger.forComponent('libp2p:tcp');
        this.opts = options;
        this.components = components;
        if (components.metrics != null) {
            this.metrics = {
                dialerEvents: components.metrics.registerCounterGroup('libp2p_tcp_dialer_events_total', {
                    label: 'event',
                    help: 'Total count of TCP dialer events by type'
                })
            };
        }
    }
    [symbol] = true;
    [Symbol.toStringTag] = '@libp2p/tcp';
    async dial(ma, options) {
        options.keepAlive = options.keepAlive ?? true;
        // options.signal destroys the socket before 'connect' event
        const socket = await this._connect(ma, options);
        // Avoid uncaught errors caused by unstable connections
        socket.on('error', err => {
            this.log('socket error', err);
        });
        const maConn = toMultiaddrConnection(socket, {
            remoteAddr: ma,
            socketInactivityTimeout: this.opts.outboundSocketInactivityTimeout,
            socketCloseTimeout: this.opts.socketCloseTimeout,
            metrics: this.metrics?.dialerEvents,
            logger: this.components.logger
        });
        const onAbort = () => {
            maConn.close().catch(err => {
                this.log.error('Error closing maConn after abort', err);
            });
        };
        options.signal?.addEventListener('abort', onAbort, { once: true });
        this.log('new outbound connection %s', maConn.remoteAddr);
        const conn = await options.upgrader.upgradeOutbound(maConn);
        this.log('outbound connection %s upgraded', maConn.remoteAddr);
        options.signal?.removeEventListener('abort', onAbort);
        if (options.signal?.aborted === true) {
            conn.close().catch(err => {
                this.log.error('Error closing conn after abort', err);
            });
            throw new AbortError();
        }
        return conn;
    }
    async _connect(ma, options) {
        if (options.signal?.aborted === true) {
            throw new AbortError();
        }
        return new Promise((resolve, reject) => {
            const start = Date.now();
            const cOpts = multiaddrToNetConfig(ma, {
                ...(this.opts.dialOpts ?? {}),
                ...options
            });
            this.log('dialing %a', ma);
            const rawSocket = net.connect(cOpts);
            const onError = (err) => {
                const cOptsStr = cOpts.path ?? `${cOpts.host ?? ''}:${cOpts.port}`;
                err.message = `connection error ${cOptsStr}: ${err.message}`;
                this.metrics?.dialerEvents.increment({ error: true });
                done(err);
            };
            const onTimeout = () => {
                this.log('connection timeout %a', ma);
                this.metrics?.dialerEvents.increment({ timeout: true });
                const err = new CodeError(`connection timeout after ${Date.now() - start}ms`, 'ERR_CONNECT_TIMEOUT');
                // Note: this will result in onError() being called
                rawSocket.emit('error', err);
            };
            const onConnect = () => {
                this.log('connection opened %a', ma);
                this.metrics?.dialerEvents.increment({ connect: true });
                done();
            };
            const onAbort = () => {
                this.log('connection aborted %a', ma);
                this.metrics?.dialerEvents.increment({ abort: true });
                rawSocket.destroy();
                done(new AbortError());
            };
            const done = (err) => {
                rawSocket.removeListener('error', onError);
                rawSocket.removeListener('timeout', onTimeout);
                rawSocket.removeListener('connect', onConnect);
                if (options.signal != null) {
                    options.signal.removeEventListener('abort', onAbort);
                }
                if (err != null) {
                    reject(err);
                    return;
                }
                resolve(rawSocket);
            };
            rawSocket.on('error', onError);
            rawSocket.on('timeout', onTimeout);
            rawSocket.on('connect', onConnect);
            if (options.signal != null) {
                options.signal.addEventListener('abort', onAbort);
            }
        });
    }
    /**
     * Creates a TCP listener. The provided `handler` function will be called
     * anytime a new incoming Connection has been successfully upgraded via
     * `upgrader.upgradeInbound`.
     */
    createListener(options) {
        return new TCPListener({
            ...(this.opts.listenOpts ?? {}),
            ...options,
            maxConnections: this.opts.maxConnections,
            backlog: this.opts.backlog,
            closeServerOnMaxConnections: this.opts.closeServerOnMaxConnections,
            socketInactivityTimeout: this.opts.inboundSocketInactivityTimeout,
            socketCloseTimeout: this.opts.socketCloseTimeout,
            metrics: this.components.metrics,
            logger: this.components.logger
        });
    }
    /**
     * Takes a list of `Multiaddr`s and returns only valid TCP addresses
     */
    filter(multiaddrs) {
        multiaddrs = Array.isArray(multiaddrs) ? multiaddrs : [multiaddrs];
        return multiaddrs.filter(ma => {
            if (ma.protoCodes().includes(CODE_CIRCUIT)) {
                return false;
            }
            if (ma.protoCodes().includes(CODE_UNIX)) {
                return true;
            }
            return mafmt.TCP.matches(ma.decapsulateCode(CODE_P2P));
        });
    }
}
export function tcp(init = {}) {
    return (components) => {
        return new TCP(components, init);
    };
}
//# sourceMappingURL=index.js.map