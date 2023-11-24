import { symbol } from '@libp2p/interface/connection';
import { CodeError } from '@libp2p/interface/errors';
import { setMaxListeners } from '@libp2p/interface/events';
const CLOSE_TIMEOUT = 500;
/**
 * An implementation of the js-libp2p connection.
 * Any libp2p transport should use an upgrader to return this connection.
 */
export class ConnectionImpl {
    /**
     * Connection identifier.
     */
    id;
    /**
     * Observed multiaddr of the remote peer
     */
    remoteAddr;
    /**
     * Remote peer id
     */
    remotePeer;
    direction;
    timeline;
    multiplexer;
    encryption;
    status;
    transient;
    log;
    /**
     * User provided tags
     *
     */
    tags;
    /**
     * Reference to the new stream function of the multiplexer
     */
    _newStream;
    /**
     * Reference to the close function of the raw connection
     */
    _close;
    _abort;
    /**
     * Reference to the getStreams function of the muxer
     */
    _getStreams;
    /**
     * An implementation of the js-libp2p connection.
     * Any libp2p transport should use an upgrader to return this connection.
     */
    constructor(init) {
        const { remoteAddr, remotePeer, newStream, close, abort, getStreams } = init;
        this.id = `${(parseInt(String(Math.random() * 1e9))).toString(36)}${Date.now()}`;
        this.remoteAddr = remoteAddr;
        this.remotePeer = remotePeer;
        this.direction = init.direction;
        this.status = 'open';
        this.timeline = init.timeline;
        this.multiplexer = init.multiplexer;
        this.encryption = init.encryption;
        this.transient = init.transient ?? false;
        this.log = init.logger.forComponent(`libp2p:connection:${this.direction}:${this.id}`);
        if (this.remoteAddr.getPeerId() == null) {
            this.remoteAddr = this.remoteAddr.encapsulate(`/p2p/${this.remotePeer}`);
        }
        this._newStream = newStream;
        this._close = close;
        this._abort = abort;
        this._getStreams = getStreams;
        this.tags = [];
    }
    [Symbol.toStringTag] = 'Connection';
    [symbol] = true;
    /**
     * Get all the streams of the muxer
     */
    get streams() {
        return this._getStreams();
    }
    /**
     * Create a new stream from this connection
     */
    async newStream(protocols, options) {
        if (this.status === 'closing') {
            throw new CodeError('the connection is being closed', 'ERR_CONNECTION_BEING_CLOSED');
        }
        if (this.status === 'closed') {
            throw new CodeError('the connection is closed', 'ERR_CONNECTION_CLOSED');
        }
        if (!Array.isArray(protocols)) {
            protocols = [protocols];
        }
        if (this.transient && options?.runOnTransientConnection !== true) {
            throw new CodeError('Cannot open protocol stream on transient connection', 'ERR_TRANSIENT_CONNECTION');
        }
        const stream = await this._newStream(protocols, options);
        stream.direction = 'outbound';
        return stream;
    }
    /**
     * Close the connection
     */
    async close(options = {}) {
        if (this.status === 'closed' || this.status === 'closing') {
            return;
        }
        this.log('closing connection to %a', this.remoteAddr);
        this.status = 'closing';
        if (options.signal == null) {
            const signal = AbortSignal.timeout(CLOSE_TIMEOUT);
            setMaxListeners(Infinity, signal);
            options = {
                ...options,
                signal
            };
        }
        try {
            this.log.trace('closing all streams');
            // close all streams gracefully - this can throw if we're not multiplexed
            await Promise.all(this.streams.map(async (s) => s.close(options)));
            this.log.trace('closing underlying transport');
            // close raw connection
            await this._close(options);
            this.log.trace('updating timeline with close time');
            this.status = 'closed';
            this.timeline.close = Date.now();
        }
        catch (err) {
            this.log.error('error encountered during graceful close of connection to %a', this.remoteAddr, err);
            this.abort(err);
        }
    }
    abort(err) {
        this.log.error('aborting connection to %a due to error', this.remoteAddr, err);
        this.status = 'closing';
        this.streams.forEach(s => { s.abort(err); });
        this.log.error('all streams aborted', this.streams.length);
        // Abort raw connection
        this._abort(err);
        this.timeline.close = Date.now();
        this.status = 'closed';
    }
}
export function createConnection(init) {
    return new ConnectionImpl(init);
}
//# sourceMappingURL=index.js.map