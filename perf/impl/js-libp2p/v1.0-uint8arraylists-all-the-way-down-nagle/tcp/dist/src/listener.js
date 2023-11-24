import net from 'net';
import { CodeError } from '@libp2p/interface/errors';
import { TypedEventEmitter, CustomEvent } from '@libp2p/interface/events';
import { CODE_P2P } from './constants.js';
import { toMultiaddrConnection } from './socket-to-conn.js';
import { getMultiaddrs, multiaddrToNetConfig } from './utils.js';
/**
 * Attempts to close the given maConn. If a failure occurs, it will be logged
 */
async function attemptClose(maConn, options) {
    try {
        await maConn.close();
    }
    catch (err) {
        options.log.error('an error occurred closing the connection', err);
    }
}
var TCPListenerStatusCode;
(function (TCPListenerStatusCode) {
    /**
     * When server object is initialized but we don't know the listening address yet or
     * the server object is stopped manually, can be resumed only by calling listen()
     **/
    TCPListenerStatusCode[TCPListenerStatusCode["INACTIVE"] = 0] = "INACTIVE";
    TCPListenerStatusCode[TCPListenerStatusCode["ACTIVE"] = 1] = "ACTIVE";
    /* During the connection limits */
    TCPListenerStatusCode[TCPListenerStatusCode["PAUSED"] = 2] = "PAUSED";
})(TCPListenerStatusCode || (TCPListenerStatusCode = {}));
export class TCPListener extends TypedEventEmitter {
    context;
    server;
    /** Keep track of open connections to destroy in case of timeout */
    connections = new Set();
    status = { code: TCPListenerStatusCode.INACTIVE };
    metrics;
    addr;
    log;
    constructor(context) {
        super();
        this.context = context;
        context.keepAlive = context.keepAlive ?? true;
        this.log = context.logger.forComponent('libp2p:tcp:listener');
        this.addr = 'unknown';
        this.server = net.createServer(context, this.onSocket.bind(this));
        // https://nodejs.org/api/net.html#servermaxconnections
        // If set reject connections when the server's connection count gets high
        // Useful to prevent too resource exhaustion via many open connections on high bursts of activity
        if (context.maxConnections !== undefined) {
            this.server.maxConnections = context.maxConnections;
        }
        if (context.closeServerOnMaxConnections != null) {
            // Sanity check options
            if (context.closeServerOnMaxConnections.closeAbove < context.closeServerOnMaxConnections.listenBelow) {
                throw new CodeError('closeAbove must be >= listenBelow', 'ERROR_CONNECTION_LIMITS');
            }
        }
        this.server
            .on('listening', () => {
            if (context.metrics != null) {
                // we are listening, register metrics for our port
                const address = this.server.address();
                if (address == null) {
                    this.addr = 'unknown';
                }
                else if (typeof address === 'string') {
                    // unix socket
                    this.addr = address;
                }
                else {
                    this.addr = `${address.address}:${address.port}`;
                }
                context.metrics?.registerMetricGroup('libp2p_tcp_inbound_connections_total', {
                    label: 'address',
                    help: 'Current active connections in TCP listener',
                    calculate: () => {
                        return {
                            [this.addr]: this.connections.size
                        };
                    }
                });
                this.metrics = {
                    status: context.metrics.registerMetricGroup('libp2p_tcp_listener_status_info', {
                        label: 'address',
                        help: 'Current status of the TCP listener socket'
                    }),
                    errors: context.metrics.registerMetricGroup('libp2p_tcp_listener_errors_total', {
                        label: 'address',
                        help: 'Total count of TCP listener errors by type'
                    }),
                    events: context.metrics.registerMetricGroup('libp2p_tcp_listener_events_total', {
                        label: 'address',
                        help: 'Total count of TCP listener events by type'
                    })
                };
                this.metrics?.status.update({
                    [this.addr]: TCPListenerStatusCode.ACTIVE
                });
            }
            this.dispatchEvent(new CustomEvent('listening'));
        })
            .on('error', err => {
            this.metrics?.errors.increment({ [`${this.addr} listen_error`]: true });
            this.dispatchEvent(new CustomEvent('error', { detail: err }));
        })
            .on('close', () => {
            this.metrics?.status.update({
                [this.addr]: this.status.code
            });
            // If this event is emitted, the transport manager will remove the listener from it's cache
            // in the meanwhile if the connections are dropped then listener will start listening again
            // and the transport manager will not be able to close the server
            if (this.status.code !== TCPListenerStatusCode.PAUSED) {
                this.dispatchEvent(new CustomEvent('close'));
            }
        });
    }
    onSocket(socket) {
        if (this.status.code !== TCPListenerStatusCode.ACTIVE) {
            throw new CodeError('Server is is not listening yet', 'ERR_SERVER_NOT_RUNNING');
        }
        // Avoid uncaught errors caused by unstable connections
        socket.on('error', err => {
            this.log('socket error', err);
            this.metrics?.events.increment({ [`${this.addr} error`]: true });
        });
        let maConn;
        try {
            maConn = toMultiaddrConnection(socket, {
                listeningAddr: this.status.listeningAddr,
                socketInactivityTimeout: this.context.socketInactivityTimeout,
                socketCloseTimeout: this.context.socketCloseTimeout,
                metrics: this.metrics?.events,
                metricPrefix: `${this.addr} `,
                logger: this.context.logger
            });
        }
        catch (err) {
            this.log.error('inbound connection failed', err);
            this.metrics?.errors.increment({ [`${this.addr} inbound_to_connection`]: true });
            return;
        }
        this.log('new inbound connection %s', maConn.remoteAddr);
        try {
            this.context.upgrader.upgradeInbound(maConn)
                .then((conn) => {
                this.log('inbound connection upgraded %s', maConn.remoteAddr);
                this.connections.add(maConn);
                socket.once('close', () => {
                    this.connections.delete(maConn);
                    if (this.context.closeServerOnMaxConnections != null &&
                        this.connections.size < this.context.closeServerOnMaxConnections.listenBelow) {
                        // The most likely case of error is if the port taken by this application is binded by
                        // another process during the time the server if closed. In that case there's not much
                        // we can do. resume() will be called again every time a connection is dropped, which
                        // acts as an eventual retry mechanism. onListenError allows the consumer act on this.
                        this.resume().catch(e => {
                            this.log.error('error attempting to listen server once connection count under limit', e);
                            this.context.closeServerOnMaxConnections?.onListenError?.(e);
                        });
                    }
                });
                if (this.context.handler != null) {
                    this.context.handler(conn);
                }
                if (this.context.closeServerOnMaxConnections != null &&
                    this.connections.size >= this.context.closeServerOnMaxConnections.closeAbove) {
                    this.pause(false).catch(e => {
                        this.log.error('error attempting to close server once connection count over limit', e);
                    });
                }
                this.dispatchEvent(new CustomEvent('connection', { detail: conn }));
            })
                .catch(async (err) => {
                this.log.error('inbound connection failed', err);
                this.metrics?.errors.increment({ [`${this.addr} inbound_upgrade`]: true });
                await attemptClose(maConn, {
                    log: this.log
                });
            })
                .catch(err => {
                this.log.error('closing inbound connection failed', err);
            });
        }
        catch (err) {
            this.log.error('inbound connection failed', err);
            attemptClose(maConn, {
                log: this.log
            })
                .catch(err => {
                this.log.error('closing inbound connection failed', err);
                this.metrics?.errors.increment({ [`${this.addr} inbound_closing_failed`]: true });
            });
        }
    }
    getAddrs() {
        if (this.status.code === TCPListenerStatusCode.INACTIVE) {
            return [];
        }
        let addrs = [];
        const address = this.server.address();
        const { listeningAddr, peerId } = this.status;
        if (address == null) {
            return [];
        }
        if (typeof address === 'string') {
            addrs = [listeningAddr];
        }
        else {
            try {
                // Because TCP will only return the IPv6 version
                // we need to capture from the passed multiaddr
                if (listeningAddr.toString().startsWith('/ip4')) {
                    addrs = addrs.concat(getMultiaddrs('ip4', address.address, address.port));
                }
                else if (address.family === 'IPv6') {
                    addrs = addrs.concat(getMultiaddrs('ip6', address.address, address.port));
                }
            }
            catch (err) {
                this.log.error('could not turn %s:%s into multiaddr', address.address, address.port, err);
            }
        }
        return addrs.map(ma => peerId != null ? ma.encapsulate(`/p2p/${peerId}`) : ma);
    }
    async listen(ma) {
        if (this.status.code === TCPListenerStatusCode.ACTIVE || this.status.code === TCPListenerStatusCode.PAUSED) {
            throw new CodeError('server is already listening', 'ERR_SERVER_ALREADY_LISTENING');
        }
        const peerId = ma.getPeerId();
        const listeningAddr = peerId == null ? ma.decapsulateCode(CODE_P2P) : ma;
        const { backlog } = this.context;
        try {
            this.status = {
                code: TCPListenerStatusCode.ACTIVE,
                listeningAddr,
                peerId,
                netConfig: multiaddrToNetConfig(listeningAddr, { backlog })
            };
            await this.resume();
        }
        catch (err) {
            this.status = { code: TCPListenerStatusCode.INACTIVE };
            throw err;
        }
    }
    async close() {
        // Close connections and server the same time to avoid any race condition
        await Promise.all([
            Promise.all(Array.from(this.connections.values()).map(async (maConn) => attemptClose(maConn, {
                log: this.log
            }))),
            this.pause(true).catch(e => {
                this.log.error('error attempting to close server once connection count over limit', e);
            })
        ]);
    }
    /**
     * Can resume a stopped or start an inert server
     */
    async resume() {
        if (this.server.listening || this.status.code === TCPListenerStatusCode.INACTIVE) {
            return;
        }
        const netConfig = this.status.netConfig;
        await new Promise((resolve, reject) => {
            // NOTE: 'listening' event is only fired on success. Any error such as port already binded, is emitted via 'error'
            this.server.once('error', reject);
            this.server.listen(netConfig, resolve);
        });
        this.status = { ...this.status, code: TCPListenerStatusCode.ACTIVE };
        this.log('Listening on %s', this.server.address());
    }
    async pause(permanent) {
        if (!this.server.listening && this.status.code === TCPListenerStatusCode.PAUSED && permanent) {
            this.status = { code: TCPListenerStatusCode.INACTIVE };
            return;
        }
        if (!this.server.listening || this.status.code !== TCPListenerStatusCode.ACTIVE) {
            return;
        }
        this.log('Closing server on %s', this.server.address());
        // NodeJS implementation tracks listening status with `this._handle` property.
        // - Server.close() sets this._handle to null immediately. If this._handle is null, ERR_SERVER_NOT_RUNNING is thrown
        // - Server.listening returns `this._handle !== null` https://github.com/nodejs/node/blob/386d761943bb1b217fba27d6b80b658c23009e60/lib/net.js#L1675
        // - Server.listen() if `this._handle !== null` throws ERR_SERVER_ALREADY_LISTEN
        //
        // NOTE: Both listen and close are technically not async actions, so it's not necessary to track
        // states 'pending-close' or 'pending-listen'
        // From docs https://nodejs.org/api/net.html#serverclosecallback
        // Stops the server from accepting new connections and keeps existing connections.
        // 'close' event is emitted only emitted when all connections are ended.
        // The optional callback will be called once the 'close' event occurs.
        // We need to set this status before closing server, so other procedures are aware
        // during the time the server is closing
        this.status = permanent ? { code: TCPListenerStatusCode.INACTIVE } : { ...this.status, code: TCPListenerStatusCode.PAUSED };
        await new Promise((resolve, reject) => {
            this.server.close(err => { (err != null) ? reject(err) : resolve(); });
        });
    }
}
//# sourceMappingURL=listener.js.map