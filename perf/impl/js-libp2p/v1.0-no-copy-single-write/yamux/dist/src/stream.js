import { CodeError } from '@libp2p/interface/errors';
import { AbstractStream } from '@libp2p/utils/abstract-stream';
import each from 'it-foreach';
import { ERR_RECV_WINDOW_EXCEEDED, ERR_STREAM_ABORT, INITIAL_STREAM_WINDOW } from './constants.js';
import { Flag, FrameType, HEADER_LENGTH } from './frame.js';
export var StreamState;
(function (StreamState) {
    StreamState[StreamState["Init"] = 0] = "Init";
    StreamState[StreamState["SYNSent"] = 1] = "SYNSent";
    StreamState[StreamState["SYNReceived"] = 2] = "SYNReceived";
    StreamState[StreamState["Established"] = 3] = "Established";
    StreamState[StreamState["Finished"] = 4] = "Finished";
})(StreamState || (StreamState = {}));
/** YamuxStream is used to represent a logical stream within a session */
export class YamuxStream extends AbstractStream {
    name;
    state;
    config;
    _id;
    /** The number of available bytes to send */
    sendWindowCapacity;
    /** Callback to notify that the sendWindowCapacity has been updated */
    sendWindowCapacityUpdate;
    /** The number of bytes available to receive in a full window */
    recvWindow;
    /** The number of available bytes to receive */
    recvWindowCapacity;
    /**
     * An 'epoch' is the time it takes to process and read data
     *
     * Used in conjunction with RTT to determine whether to increase the recvWindow
     */
    epochStart;
    getRTT;
    sendFrame;
    constructor(init) {
        super({
            ...init,
            onEnd: (err) => {
                this.state = StreamState.Finished;
                init.onEnd?.(err);
            }
        });
        this.config = init.config;
        this._id = parseInt(init.id, 10);
        this.name = init.name;
        this.state = init.state;
        this.sendWindowCapacity = INITIAL_STREAM_WINDOW;
        this.recvWindow = this.config.initialStreamWindowSize;
        this.recvWindowCapacity = this.recvWindow;
        this.epochStart = Date.now();
        this.getRTT = init.getRTT;
        this.sendFrame = init.sendFrame;
        this.source = each(this.source, () => {
            this.sendWindowUpdate();
        });
    }
    /**
     * Send a message to the remote muxer informing them a new stream is being
     * opened.
     *
     * This is a noop for Yamux because the first window update is sent when
     * .newStream is called on the muxer which opens the stream on the remote.
     */
    async sendNewStream() {
    }
    /**
     * Send a data message to the remote muxer
     */
    async sendData(buf, options = {}) {
        buf = buf.sublist();
        // send in chunks, waiting for window updates
        while (buf.byteLength !== 0) {
            // wait for the send window to refill
            if (this.sendWindowCapacity === 0) {
                await this.waitForSendWindowCapacity(options);
            }
            // check we didn't close while waiting for send window capacity
            if (this.status !== 'open') {
                return;
            }
            // send as much as we can
            const toSend = Math.min(this.sendWindowCapacity, this.config.maxMessageSize - HEADER_LENGTH, buf.length);
            const flags = this.getSendFlags();
            this.sendFrame({
                type: FrameType.Data,
                flag: flags,
                streamID: this._id,
                length: toSend
            }, buf.sublist(0, toSend));
            this.sendWindowCapacity -= toSend;
            buf.consume(toSend);
        }
    }
    /**
     * Send a reset message to the remote muxer
     */
    async sendReset() {
        this.sendFrame({
            type: FrameType.WindowUpdate,
            flag: Flag.RST,
            streamID: this._id,
            length: 0
        });
    }
    /**
     * Send a message to the remote muxer, informing them no more data messages
     * will be sent by this end of the stream
     */
    async sendCloseWrite() {
        const flags = this.getSendFlags() | Flag.FIN;
        this.sendFrame({
            type: FrameType.WindowUpdate,
            flag: flags,
            streamID: this._id,
            length: 0
        });
    }
    /**
     * Send a message to the remote muxer, informing them no more data messages
     * will be read by this end of the stream
     */
    async sendCloseRead() {
    }
    /**
     * Wait for the send window to be non-zero
     *
     * Will throw with ERR_STREAM_ABORT if the stream gets aborted
     */
    async waitForSendWindowCapacity(options = {}) {
        if (this.sendWindowCapacity > 0) {
            return;
        }
        let resolve;
        let reject;
        const abort = () => {
            if (this.status === 'open') {
                reject(new CodeError('stream aborted', ERR_STREAM_ABORT));
            }
            else {
                // the stream was closed already, ignore the failure to send
                resolve();
            }
        };
        options.signal?.addEventListener('abort', abort);
        try {
            await new Promise((_resolve, _reject) => {
                this.sendWindowCapacityUpdate = () => {
                    _resolve();
                };
                reject = _reject;
                resolve = _resolve;
            });
        }
        finally {
            options.signal?.removeEventListener('abort', abort);
        }
    }
    /**
     * handleWindowUpdate is called when the stream receives a window update frame
     */
    handleWindowUpdate(header) {
        this.log?.trace('stream received window update id=%s', this._id);
        this.processFlags(header.flag);
        // increase send window
        const available = this.sendWindowCapacity;
        this.sendWindowCapacity += header.length;
        // if the update increments a 0 availability, notify the stream that sending can resume
        if (available === 0 && header.length > 0) {
            this.sendWindowCapacityUpdate?.();
        }
    }
    /**
     * handleData is called when the stream receives a data frame
     */
    async handleData(header, readData) {
        this.log?.trace('stream received data id=%s', this._id);
        this.processFlags(header.flag);
        // check that our recv window is not exceeded
        if (this.recvWindowCapacity < header.length) {
            throw new CodeError('receive window exceeded', ERR_RECV_WINDOW_EXCEEDED, { available: this.recvWindowCapacity, recv: header.length });
        }
        const data = await readData();
        this.recvWindowCapacity -= header.length;
        this.sourcePush(data);
    }
    /**
     * processFlags is used to update the state of the stream based on set flags, if any.
     */
    processFlags(flags) {
        if ((flags & Flag.ACK) === Flag.ACK) {
            if (this.state === StreamState.SYNSent) {
                this.state = StreamState.Established;
            }
        }
        if ((flags & Flag.FIN) === Flag.FIN) {
            this.remoteCloseWrite();
        }
        if ((flags & Flag.RST) === Flag.RST) {
            this.reset();
        }
    }
    /**
     * getSendFlags determines any flags that are appropriate
     * based on the current stream state.
     *
     * The state is updated as a side-effect.
     */
    getSendFlags() {
        switch (this.state) {
            case StreamState.Init:
                this.state = StreamState.SYNSent;
                return Flag.SYN;
            case StreamState.SYNReceived:
                this.state = StreamState.Established;
                return Flag.ACK;
            default:
                return 0;
        }
    }
    /**
     * potentially sends a window update enabling further writes to take place.
     */
    sendWindowUpdate() {
        // determine the flags if any
        const flags = this.getSendFlags();
        // If the stream has already been established
        // and we've processed data within the time it takes for 4 round trips
        // then we (up to) double the recvWindow
        const now = Date.now();
        const rtt = this.getRTT();
        if (flags === 0 && rtt > -1 && now - this.epochStart < rtt * 4) {
            // we've already validated that maxStreamWindowSize can't be more than MAX_UINT32
            this.recvWindow = Math.min(this.recvWindow * 2, this.config.maxStreamWindowSize);
        }
        if (this.recvWindowCapacity >= this.recvWindow && flags === 0) {
            // a window update isn't needed
            return;
        }
        // update the receive window
        const delta = this.recvWindow - this.recvWindowCapacity;
        this.recvWindowCapacity = this.recvWindow;
        // update the epoch start
        this.epochStart = now;
        // send window update
        this.sendFrame({
            type: FrameType.WindowUpdate,
            flag: flags,
            streamID: this._id,
            length: delta
        });
    }
}
//# sourceMappingURL=stream.js.map