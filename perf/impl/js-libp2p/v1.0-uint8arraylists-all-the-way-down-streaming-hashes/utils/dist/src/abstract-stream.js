import { CodeError } from '@libp2p/interface/errors';
import { pushable } from 'it-pushable';
import defer, {} from 'p-defer';
import { raceSignal } from 'race-signal';
import { Uint8ArrayList } from 'uint8arraylist';
import { closeSource } from './close-source.js';
const ERR_STREAM_RESET = 'ERR_STREAM_RESET';
const ERR_SINK_INVALID_STATE = 'ERR_SINK_INVALID_STATE';
const DEFAULT_SEND_CLOSE_WRITE_TIMEOUT = 5000;
function isPromise(thing) {
    if (thing == null) {
        return false;
    }
    return typeof thing.then === 'function' &&
        typeof thing.catch === 'function' &&
        typeof thing.finally === 'function';
}
export class AbstractStream {
    id;
    direction;
    timeline;
    protocol;
    metadata;
    source;
    status;
    readStatus;
    writeStatus;
    log;
    sinkController;
    sinkEnd;
    closed;
    endErr;
    streamSource;
    onEnd;
    onCloseRead;
    onCloseWrite;
    onReset;
    onAbort;
    sendCloseWriteTimeout;
    constructor(init) {
        this.sinkController = new AbortController();
        this.sinkEnd = defer();
        this.closed = defer();
        this.log = init.log;
        // stream status
        this.status = 'open';
        this.readStatus = 'ready';
        this.writeStatus = 'ready';
        this.id = init.id;
        this.metadata = init.metadata ?? {};
        this.direction = init.direction;
        this.timeline = {
            open: Date.now()
        };
        this.sendCloseWriteTimeout = init.sendCloseWriteTimeout ?? DEFAULT_SEND_CLOSE_WRITE_TIMEOUT;
        this.onEnd = init.onEnd;
        this.onCloseRead = init?.onCloseRead;
        this.onCloseWrite = init?.onCloseWrite;
        this.onReset = init?.onReset;
        this.onAbort = init?.onAbort;
        this.source = this.streamSource = pushable({
            onEnd: (err) => {
                if (err != null) {
                    this.log.trace('source ended with error', err);
                }
                else {
                    this.log.trace('source ended');
                }
                this.onSourceEnd(err);
            }
        });
        // necessary because the libp2p upgrader wraps the sink function
        this.sink = this.sink.bind(this);
    }
    async sink(source) {
        if (this.writeStatus !== 'ready') {
            throw new CodeError(`writable end state is "${this.writeStatus}" not "ready"`, ERR_SINK_INVALID_STATE);
        }
        try {
            this.writeStatus = 'writing';
            const options = {
                signal: this.sinkController.signal
            };
            if (this.direction === 'outbound') { // If initiator, open a new stream
                const res = this.sendNewStream(options);
                if (isPromise(res)) {
                    await res;
                }
            }
            const abortListener = () => {
                closeSource(source, this.log);
            };
            try {
                this.sinkController.signal.addEventListener('abort', abortListener);
                this.log.trace('sink reading from source');
                for await (let data of source) {
                    data = data instanceof Uint8Array ? new Uint8ArrayList(data) : data;
                    const res = this.sendData(data, options);
                    if (isPromise(res)) { // eslint-disable-line max-depth
                        await res;
                    }
                }
            }
            finally {
                this.sinkController.signal.removeEventListener('abort', abortListener);
            }
            this.log.trace('sink finished reading from source, write status is "%s"', this.writeStatus);
            if (this.writeStatus === 'writing') {
                this.writeStatus = 'closing';
                this.log.trace('send close write to remote');
                await this.sendCloseWrite({
                    signal: AbortSignal.timeout(this.sendCloseWriteTimeout)
                });
                this.writeStatus = 'closed';
            }
            this.onSinkEnd();
        }
        catch (err) {
            this.log.trace('sink ended with error, calling abort with error', err);
            this.abort(err);
            throw err;
        }
        finally {
            this.log.trace('resolve sink end');
            this.sinkEnd.resolve();
        }
    }
    onSourceEnd(err) {
        if (this.timeline.closeRead != null) {
            return;
        }
        this.timeline.closeRead = Date.now();
        this.readStatus = 'closed';
        if (err != null && this.endErr == null) {
            this.endErr = err;
        }
        this.onCloseRead?.();
        if (this.timeline.closeWrite != null) {
            this.log.trace('source and sink ended');
            this.timeline.close = Date.now();
            if (this.status !== 'aborted' && this.status !== 'reset') {
                this.status = 'closed';
            }
            if (this.onEnd != null) {
                this.onEnd(this.endErr);
            }
            this.closed.resolve();
        }
        else {
            this.log.trace('source ended, waiting for sink to end');
        }
    }
    onSinkEnd(err) {
        if (this.timeline.closeWrite != null) {
            return;
        }
        this.timeline.closeWrite = Date.now();
        this.writeStatus = 'closed';
        if (err != null && this.endErr == null) {
            this.endErr = err;
        }
        this.onCloseWrite?.();
        if (this.timeline.closeRead != null) {
            this.log.trace('sink and source ended');
            this.timeline.close = Date.now();
            if (this.status !== 'aborted' && this.status !== 'reset') {
                this.status = 'closed';
            }
            if (this.onEnd != null) {
                this.onEnd(this.endErr);
            }
            this.closed.resolve();
        }
        else {
            this.log.trace('sink ended, waiting for source to end');
        }
    }
    // Close for both Reading and Writing
    async close(options) {
        this.log.trace('closing gracefully');
        this.status = 'closing';
        await Promise.all([
            this.closeRead(options),
            this.closeWrite(options)
        ]);
        // wait for read and write ends to close
        await raceSignal(this.closed.promise, options?.signal);
        this.status = 'closed';
        this.log.trace('closed gracefully');
    }
    async closeRead(options = {}) {
        if (this.readStatus === 'closing' || this.readStatus === 'closed') {
            return;
        }
        this.log.trace('closing readable end of stream with starting read status "%s"', this.readStatus);
        const readStatus = this.readStatus;
        this.readStatus = 'closing';
        if (this.status !== 'reset' && this.status !== 'aborted' && this.timeline.closeRead == null) {
            this.log.trace('send close read to remote');
            await this.sendCloseRead(options);
        }
        if (readStatus === 'ready') {
            this.log.trace('ending internal source queue with %d queued bytes', this.streamSource.readableLength);
            this.streamSource.end();
        }
        this.log.trace('closed readable end of stream');
    }
    async closeWrite(options = {}) {
        if (this.writeStatus === 'closing' || this.writeStatus === 'closed') {
            return;
        }
        this.log.trace('closing writable end of stream with starting write status "%s"', this.writeStatus);
        if (this.writeStatus === 'ready') {
            this.log.trace('sink was never sunk, sink an empty array');
            await raceSignal(this.sink([]), options.signal);
        }
        if (this.writeStatus === 'writing') {
            // stop reading from the source passed to `.sink` in the microtask queue
            // - this lets any data queued by the user in the current tick get read
            // before we exit
            await new Promise((resolve, reject) => {
                queueMicrotask(() => {
                    this.log.trace('aborting source passed to .sink');
                    this.sinkController.abort();
                    raceSignal(this.sinkEnd.promise, options.signal)
                        .then(resolve, reject);
                });
            });
        }
        this.writeStatus = 'closed';
        this.log.trace('closed writable end of stream');
    }
    /**
     * Close immediately for reading and writing and send a reset message (local
     * error)
     */
    abort(err) {
        if (this.status === 'closed' || this.status === 'aborted' || this.status === 'reset') {
            return;
        }
        this.log('abort with error', err);
        // try to send a reset message
        this.log('try to send reset to remote');
        const res = this.sendReset();
        if (isPromise(res)) {
            res.catch((err) => {
                this.log.error('error sending reset message', err);
            });
        }
        this.status = 'aborted';
        this.timeline.abort = Date.now();
        this._closeSinkAndSource(err);
        this.onAbort?.(err);
    }
    /**
     * Receive a reset message - close immediately for reading and writing (remote
     * error)
     */
    reset() {
        if (this.status === 'closed' || this.status === 'aborted' || this.status === 'reset') {
            return;
        }
        const err = new CodeError('stream reset', ERR_STREAM_RESET);
        this.status = 'reset';
        this.timeline.reset = Date.now();
        this._closeSinkAndSource(err);
        this.onReset?.();
    }
    _closeSinkAndSource(err) {
        this._closeSink(err);
        this._closeSource(err);
    }
    _closeSink(err) {
        // if the sink function is running, cause it to end
        if (this.writeStatus === 'writing') {
            this.log.trace('end sink source');
            this.sinkController.abort();
        }
        this.onSinkEnd(err);
    }
    _closeSource(err) {
        // if the source is not ending, end it
        if (this.readStatus !== 'closing' && this.readStatus !== 'closed') {
            this.log.trace('ending source with %d bytes to be read by consumer', this.streamSource.readableLength);
            this.readStatus = 'closing';
            this.streamSource.end(err);
        }
    }
    /**
     * The remote closed for writing so we should expect to receive no more
     * messages
     */
    remoteCloseWrite() {
        if (this.readStatus === 'closing' || this.readStatus === 'closed') {
            this.log('received remote close write but local source is already closed');
            return;
        }
        this.log.trace('remote close write');
        this._closeSource();
    }
    /**
     * The remote closed for reading so we should not send any more
     * messages
     */
    remoteCloseRead() {
        if (this.writeStatus === 'closing' || this.writeStatus === 'closed') {
            this.log('received remote close read but local sink is already closed');
            return;
        }
        this.log.trace('remote close read');
        this._closeSink();
    }
    /**
     * The underlying muxer has closed, no more messages can be sent or will
     * be received, close immediately to free up resources
     */
    destroy() {
        if (this.status === 'closed' || this.status === 'aborted' || this.status === 'reset') {
            this.log('received destroy but we are already closed');
            return;
        }
        this.log.trace('stream destroyed');
        this._closeSinkAndSource();
    }
    /**
     * When an extending class reads data from it's implementation-specific source,
     * call this method to allow the stream consumer to read the data.
     */
    sourcePush(data) {
        this.streamSource.push(data);
    }
    /**
     * Returns the amount of unread data - can be used to prevent large amounts of
     * data building up when the stream consumer is too slow.
     */
    sourceReadableLength() {
        return this.streamSource.readableLength;
    }
}
//# sourceMappingURL=abstract-stream.js.map