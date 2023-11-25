import { CodeError } from '@libp2p/interface/errors';
import { setMaxListeners } from '@libp2p/interface/events';
import { logger } from '@libp2p/logger';
import { getIterator } from 'get-iterator';
import { pushable } from 'it-pushable';
import { Uint8ArrayList } from 'uint8arraylist';
import { defaultConfig, verifyConfig } from './config.js';
import { ERR_BOTH_CLIENTS, ERR_INVALID_FRAME, ERR_MAX_OUTBOUND_STREAMS_EXCEEDED, ERR_MUXER_LOCAL_CLOSED, ERR_MUXER_REMOTE_CLOSED, ERR_NOT_MATCHING_PING, ERR_STREAM_ALREADY_EXISTS, ERR_UNREQUESTED_PING, PROTOCOL_ERRORS } from './constants.js';
import { Decoder } from './decode.js';
import { encodeHeader } from './encode.js';
import { Flag, FrameType, GoAwayCode } from './frame.js';
import { StreamState, YamuxStream } from './stream.js';
const YAMUX_PROTOCOL_ID = '/yamux/1.0.0';
const CLOSE_TIMEOUT = 500;
export class Yamux {
    protocol = YAMUX_PROTOCOL_ID;
    _init;
    constructor(init = {}) {
        this._init = init;
    }
    createStreamMuxer(init) {
        return new YamuxMuxer({
            ...this._init,
            ...init
        });
    }
}
export class YamuxMuxer {
    protocol = YAMUX_PROTOCOL_ID;
    source;
    sink;
    config;
    log;
    /** Used to close the muxer from either the sink or source */
    closeController;
    /** The next stream id to be used when initiating a new stream */
    nextStreamID;
    /** Primary stream mapping, streamID => stream */
    _streams;
    /** The next ping id to be used when pinging */
    nextPingID;
    /** Tracking info for the currently active ping */
    activePing;
    /** Round trip time */
    rtt;
    /** True if client, false if server */
    client;
    localGoAway;
    remoteGoAway;
    /** Number of tracked inbound streams */
    numInboundStreams;
    /** Number of tracked outbound streams */
    numOutboundStreams;
    onIncomingStream;
    onStreamEnd;
    constructor(init) {
        this.client = init.direction === 'outbound';
        this.config = { ...defaultConfig, ...init };
        this.log = this.config.log;
        verifyConfig(this.config);
        this.closeController = new AbortController();
        setMaxListeners(Infinity, this.closeController.signal);
        this.onIncomingStream = init.onIncomingStream;
        this.onStreamEnd = init.onStreamEnd;
        this._streams = new Map();
        this.source = pushable({
            onEnd: () => {
                this.log?.trace('muxer source ended');
                this._streams.forEach(stream => {
                    stream.destroy();
                });
            }
        });
        this.sink = async (source) => {
            const shutDownListener = () => {
                const iterator = getIterator(source);
                if (iterator.return != null) {
                    const res = iterator.return();
                    if (isPromise(res)) {
                        res.catch(err => {
                            this.log?.('could not cause sink source to return', err);
                        });
                    }
                }
            };
            let reason, error;
            try {
                const decoder = new Decoder(source);
                try {
                    this.closeController.signal.addEventListener('abort', shutDownListener);
                    for await (const frame of decoder.emitFrames()) {
                        await this.handleFrame(frame.header, frame.readData);
                    }
                }
                finally {
                    this.closeController.signal.removeEventListener('abort', shutDownListener);
                }
                reason = GoAwayCode.NormalTermination;
            }
            catch (err) {
                // either a protocol or internal error
                const errCode = err.code;
                if (PROTOCOL_ERRORS.has(errCode)) {
                    this.log?.error('protocol error in sink', err);
                    reason = GoAwayCode.ProtocolError;
                }
                else {
                    this.log?.error('internal error in sink', err);
                    reason = GoAwayCode.InternalError;
                }
                error = err;
            }
            this.log?.trace('muxer sink ended');
            if (error != null) {
                this.abort(error, reason);
            }
            else {
                await this.close({ reason });
            }
        };
        this.numInboundStreams = 0;
        this.numOutboundStreams = 0;
        // client uses odd streamIDs, server uses even streamIDs
        this.nextStreamID = this.client ? 1 : 2;
        this.nextPingID = 0;
        this.rtt = -1;
        this.log?.trace('muxer created');
        if (this.config.enableKeepAlive) {
            this.keepAliveLoop().catch(e => this.log?.error('keepalive error: %s', e));
        }
        // send an initial ping to establish RTT
        this.ping().catch(e => this.log?.error('ping error: %s', e));
    }
    get streams() {
        return Array.from(this._streams.values());
    }
    newStream(name) {
        if (this.remoteGoAway !== undefined) {
            throw new CodeError('muxer closed remotely', ERR_MUXER_REMOTE_CLOSED);
        }
        if (this.localGoAway !== undefined) {
            throw new CodeError('muxer closed locally', ERR_MUXER_LOCAL_CLOSED);
        }
        const id = this.nextStreamID;
        this.nextStreamID += 2;
        // check against our configured maximum number of outbound streams
        if (this.numOutboundStreams >= this.config.maxOutboundStreams) {
            throw new CodeError('max outbound streams exceeded', ERR_MAX_OUTBOUND_STREAMS_EXCEEDED);
        }
        this.log?.trace('new outgoing stream id=%s', id);
        const stream = this._newStream(id, name, StreamState.Init, 'outbound');
        this._streams.set(id, stream);
        this.numOutboundStreams++;
        // send a window update to open the stream on the receiver end
        stream.sendWindowUpdate();
        return stream;
    }
    /**
     * Initiate a ping and wait for a response
     *
     * Note: only a single ping will be initiated at a time.
     * If a ping is already in progress, a new ping will not be initiated.
     *
     * @returns the round-trip-time in milliseconds
     */
    async ping() {
        if (this.remoteGoAway !== undefined) {
            throw new CodeError('muxer closed remotely', ERR_MUXER_REMOTE_CLOSED);
        }
        if (this.localGoAway !== undefined) {
            throw new CodeError('muxer closed locally', ERR_MUXER_LOCAL_CLOSED);
        }
        // An active ping does not yet exist, handle the process here
        if (this.activePing === undefined) {
            // create active ping
            let _resolve = () => { };
            this.activePing = {
                id: this.nextPingID++,
                // this promise awaits resolution or the close controller aborting
                promise: new Promise((resolve, reject) => {
                    const closed = () => {
                        reject(new CodeError('muxer closed locally', ERR_MUXER_LOCAL_CLOSED));
                    };
                    this.closeController.signal.addEventListener('abort', closed, { once: true });
                    _resolve = () => {
                        this.closeController.signal.removeEventListener('abort', closed);
                        resolve();
                    };
                }),
                resolve: _resolve
            };
            // send ping
            const start = Date.now();
            this.sendPing(this.activePing.id);
            // await pong
            try {
                await this.activePing.promise;
            }
            finally {
                // clean-up active ping
                delete this.activePing;
            }
            // update rtt
            const end = Date.now();
            this.rtt = end - start;
        }
        else {
            // an active ping is already in progress, piggyback off that
            await this.activePing.promise;
        }
        return this.rtt;
    }
    /**
     * Get the ping round trip time
     *
     * Note: Will return 0 if no successful ping has yet been completed
     *
     * @returns the round-trip-time in milliseconds
     */
    getRTT() {
        return this.rtt;
    }
    /**
     * Close the muxer
     */
    async close(options = {}) {
        if (this.closeController.signal.aborted) {
            // already closed
            return;
        }
        const reason = options?.reason ?? GoAwayCode.NormalTermination;
        this.log?.trace('muxer close reason=%s', reason);
        if (options.signal == null) {
            const signal = AbortSignal.timeout(CLOSE_TIMEOUT);
            setMaxListeners(Infinity, signal);
            options = {
                ...options,
                signal
            };
        }
        try {
            await Promise.all([...this._streams.values()].map(async (s) => s.close(options)));
            // send reason to the other side, allow the other side to close gracefully
            this.sendGoAway(reason);
            this._closeMuxer();
        }
        catch (err) {
            this.abort(err);
        }
    }
    abort(err, reason) {
        if (this.closeController.signal.aborted) {
            // already closed
            return;
        }
        reason = reason ?? GoAwayCode.InternalError;
        // If reason was provided, use that, otherwise use the presence of `err` to determine the reason
        this.log?.error('muxer abort reason=%s error=%s', reason, err);
        // Abort all underlying streams
        for (const stream of this._streams.values()) {
            stream.abort(err);
        }
        // send reason to the other side, allow the other side to close gracefully
        this.sendGoAway(reason);
        this._closeMuxer();
    }
    isClosed() {
        return this.closeController.signal.aborted;
    }
    /**
     * Called when either the local or remote shuts down the muxer
     */
    _closeMuxer() {
        // stop the sink and any other processes
        this.closeController.abort();
        // stop the source
        this.source.end();
    }
    /** Create a new stream */
    _newStream(id, name, state, direction) {
        if (this._streams.get(id) != null) {
            throw new CodeError('Stream already exists', ERR_STREAM_ALREADY_EXISTS, { id });
        }
        const stream = new YamuxStream({
            id: id.toString(),
            name,
            state,
            direction,
            sendFrame: this.sendFrame.bind(this),
            onEnd: () => {
                this.closeStream(id);
                this.onStreamEnd?.(stream);
            },
            log: logger(`libp2p:yamux:${direction}:${id}`),
            config: this.config,
            getRTT: this.getRTT.bind(this)
        });
        return stream;
    }
    /**
     * closeStream is used to close a stream once both sides have
     * issued a close.
     */
    closeStream(id) {
        if (this.client === (id % 2 === 0)) {
            this.numInboundStreams--;
        }
        else {
            this.numOutboundStreams--;
        }
        this._streams.delete(id);
    }
    async keepAliveLoop() {
        const abortPromise = new Promise((_resolve, reject) => { this.closeController.signal.addEventListener('abort', reject, { once: true }); });
        this.log?.trace('muxer keepalive enabled interval=%s', this.config.keepAliveInterval);
        while (true) {
            let timeoutId;
            try {
                await Promise.race([
                    abortPromise,
                    new Promise((resolve) => {
                        timeoutId = setTimeout(resolve, this.config.keepAliveInterval);
                    })
                ]);
                this.ping().catch(e => this.log?.error('ping error: %s', e));
            }
            catch (e) {
                // closed
                clearInterval(timeoutId);
                return;
            }
        }
    }
    async handleFrame(header, readData) {
        const { streamID, type, length } = header;
        this.log?.trace('received frame %o', header);
        if (streamID === 0) {
            switch (type) {
                case FrameType.Ping:
                    {
                        this.handlePing(header);
                        return;
                    }
                case FrameType.GoAway:
                    {
                        this.handleGoAway(length);
                        return;
                    }
                default:
                    // Invalid state
                    throw new CodeError('Invalid frame type', ERR_INVALID_FRAME, { header });
            }
        }
        else {
            switch (header.type) {
                case FrameType.Data:
                case FrameType.WindowUpdate:
                    {
                        await this.handleStreamMessage(header, readData);
                        return;
                    }
                default:
                    // Invalid state
                    throw new CodeError('Invalid frame type', ERR_INVALID_FRAME, { header });
            }
        }
    }
    handlePing(header) {
        // If the ping  is initiated by the sender, send a response
        if (header.flag === Flag.SYN) {
            this.log?.trace('received ping request pingId=%s', header.length);
            this.sendPing(header.length, Flag.ACK);
        }
        else if (header.flag === Flag.ACK) {
            this.log?.trace('received ping response pingId=%s', header.length);
            this.handlePingResponse(header.length);
        }
        else {
            // Invalid state
            throw new CodeError('Invalid frame flag', ERR_INVALID_FRAME, { header });
        }
    }
    handlePingResponse(pingId) {
        if (this.activePing === undefined) {
            // this ping was not requested
            throw new CodeError('ping not requested', ERR_UNREQUESTED_PING);
        }
        if (this.activePing.id !== pingId) {
            // this ping doesn't match our active ping request
            throw new CodeError('ping doesn\'t match our id', ERR_NOT_MATCHING_PING);
        }
        // valid ping response
        this.activePing.resolve();
    }
    handleGoAway(reason) {
        this.log?.trace('received GoAway reason=%s', GoAwayCode[reason] ?? 'unknown');
        this.remoteGoAway = reason;
        // If the other side is friendly, they would have already closed all streams before sending a GoAway
        // In case they weren't, reset all streams
        for (const stream of this._streams.values()) {
            stream.reset();
        }
        this._closeMuxer();
    }
    async handleStreamMessage(header, readData) {
        const { streamID, flag, type } = header;
        if ((flag & Flag.SYN) === Flag.SYN) {
            this.incomingStream(streamID);
        }
        const stream = this._streams.get(streamID);
        if (stream === undefined) {
            if (type === FrameType.Data) {
                this.log?.('discarding data for stream id=%s', streamID);
                if (readData === undefined) {
                    throw new Error('unreachable');
                }
                await readData();
            }
            else {
                this.log?.('frame for missing stream id=%s', streamID);
            }
            return;
        }
        switch (type) {
            case FrameType.WindowUpdate: {
                stream.handleWindowUpdate(header);
                return;
            }
            case FrameType.Data: {
                if (readData === undefined) {
                    throw new Error('unreachable');
                }
                await stream.handleData(header, readData);
                return;
            }
            default:
                throw new Error('unreachable');
        }
    }
    incomingStream(id) {
        if (this.client !== (id % 2 === 0)) {
            throw new CodeError('both endpoints are clients', ERR_BOTH_CLIENTS);
        }
        if (this._streams.has(id)) {
            return;
        }
        this.log?.trace('new incoming stream id=%s', id);
        if (this.localGoAway !== undefined) {
            // reject (reset) immediately if we are doing a go away
            this.sendFrame({
                type: FrameType.WindowUpdate,
                flag: Flag.RST,
                streamID: id,
                length: 0
            });
            return;
        }
        // check against our configured maximum number of inbound streams
        if (this.numInboundStreams >= this.config.maxInboundStreams) {
            this.log?.('maxIncomingStreams exceeded, forcing stream reset');
            this.sendFrame({
                type: FrameType.WindowUpdate,
                flag: Flag.RST,
                streamID: id,
                length: 0
            });
            return;
        }
        // allocate a new stream
        const stream = this._newStream(id, undefined, StreamState.SYNReceived, 'inbound');
        this.numInboundStreams++;
        // the stream should now be tracked
        this._streams.set(id, stream);
        this.onIncomingStream?.(stream);
    }
    sendFrame(header, data) {
        this.log?.trace('sending frame %o', header);
        if (header.type === FrameType.Data) {
            if (data === undefined) {
                throw new CodeError('invalid frame', ERR_INVALID_FRAME);
            }
            this.source.push(new Uint8ArrayList(encodeHeader(header), data));
        }
        else {
            this.source.push(encodeHeader(header));
        }
    }
    sendPing(pingId, flag = Flag.SYN) {
        if (flag === Flag.SYN) {
            this.log?.trace('sending ping request pingId=%s', pingId);
        }
        else {
            this.log?.trace('sending ping response pingId=%s', pingId);
        }
        this.sendFrame({
            type: FrameType.Ping,
            flag,
            streamID: 0,
            length: pingId
        });
    }
    sendGoAway(reason = GoAwayCode.NormalTermination) {
        this.log?.('sending GoAway reason=%s', GoAwayCode[reason]);
        this.localGoAway = reason;
        this.sendFrame({
            type: FrameType.GoAway,
            flag: 0,
            streamID: 0,
            length: reason
        });
    }
}
function isPromise(thing) {
    return thing != null && typeof thing.then === 'function';
}
//# sourceMappingURL=muxer.js.map