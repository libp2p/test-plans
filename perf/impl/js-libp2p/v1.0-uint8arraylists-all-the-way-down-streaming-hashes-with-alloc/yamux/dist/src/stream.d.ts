import { AbstractStream, type AbstractStreamInit } from '@libp2p/utils/abstract-stream';
import { type FrameHeader } from './frame.js';
import type { Config } from './config.js';
import type { AbortOptions } from '@libp2p/interface';
import type { Uint8ArrayList } from 'uint8arraylist';
export declare enum StreamState {
    Init = 0,
    SYNSent = 1,
    SYNReceived = 2,
    Established = 3,
    Finished = 4
}
export interface YamuxStreamInit extends AbstractStreamInit {
    name?: string;
    sendFrame: (header: FrameHeader, body?: Uint8ArrayList) => void;
    getRTT: () => number;
    config: Config;
    state: StreamState;
}
/** YamuxStream is used to represent a logical stream within a session */
export declare class YamuxStream extends AbstractStream {
    name?: string;
    state: StreamState;
    private readonly config;
    private readonly _id;
    /** The number of available bytes to send */
    private sendWindowCapacity;
    /** Callback to notify that the sendWindowCapacity has been updated */
    private sendWindowCapacityUpdate?;
    /** The number of bytes available to receive in a full window */
    private recvWindow;
    /** The number of available bytes to receive */
    private recvWindowCapacity;
    /**
     * An 'epoch' is the time it takes to process and read data
     *
     * Used in conjunction with RTT to determine whether to increase the recvWindow
     */
    private epochStart;
    private readonly getRTT;
    private readonly sendFrame;
    constructor(init: YamuxStreamInit);
    /**
     * Send a message to the remote muxer informing them a new stream is being
     * opened.
     *
     * This is a noop for Yamux because the first window update is sent when
     * .newStream is called on the muxer which opens the stream on the remote.
     */
    sendNewStream(): Promise<void>;
    /**
     * Send a data message to the remote muxer
     */
    sendData(buf: Uint8ArrayList, options?: AbortOptions): Promise<void>;
    /**
     * Send a reset message to the remote muxer
     */
    sendReset(): Promise<void>;
    /**
     * Send a message to the remote muxer, informing them no more data messages
     * will be sent by this end of the stream
     */
    sendCloseWrite(): Promise<void>;
    /**
     * Send a message to the remote muxer, informing them no more data messages
     * will be read by this end of the stream
     */
    sendCloseRead(): Promise<void>;
    /**
     * Wait for the send window to be non-zero
     *
     * Will throw with ERR_STREAM_ABORT if the stream gets aborted
     */
    waitForSendWindowCapacity(options?: AbortOptions): Promise<void>;
    /**
     * handleWindowUpdate is called when the stream receives a window update frame
     */
    handleWindowUpdate(header: FrameHeader): void;
    /**
     * handleData is called when the stream receives a data frame
     */
    handleData(header: FrameHeader, readData: () => Promise<Uint8ArrayList>): Promise<void>;
    /**
     * processFlags is used to update the state of the stream based on set flags, if any.
     */
    private processFlags;
    /**
     * getSendFlags determines any flags that are appropriate
     * based on the current stream state.
     *
     * The state is updated as a side-effect.
     */
    private getSendFlags;
    /**
     * potentially sends a window update enabling further writes to take place.
     */
    sendWindowUpdate(): void;
}
//# sourceMappingURL=stream.d.ts.map