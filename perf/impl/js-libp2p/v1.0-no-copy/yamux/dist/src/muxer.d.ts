import { type Pushable } from 'it-pushable';
import { Uint8ArrayList } from 'uint8arraylist';
import { type Config } from './config.js';
import { GoAwayCode } from './frame.js';
import { YamuxStream } from './stream.js';
import type { AbortOptions } from '@libp2p/interface';
import type { StreamMuxer, StreamMuxerFactory, StreamMuxerInit } from '@libp2p/interface/stream-muxer';
import type { Sink, Source } from 'it-stream-types';
export interface YamuxMuxerInit extends StreamMuxerInit, Partial<Config> {
}
export declare class Yamux implements StreamMuxerFactory {
    protocol: string;
    private readonly _init;
    constructor(init?: YamuxMuxerInit);
    createStreamMuxer(init?: YamuxMuxerInit): YamuxMuxer;
}
export interface CloseOptions extends AbortOptions {
    reason?: GoAwayCode;
}
export declare class YamuxMuxer implements StreamMuxer {
    protocol: string;
    source: Pushable<Uint8ArrayList | Uint8Array>;
    sink: Sink<Source<Uint8ArrayList | Uint8Array>, Promise<void>>;
    private readonly config;
    private readonly log?;
    /** Used to close the muxer from either the sink or source */
    private readonly closeController;
    /** The next stream id to be used when initiating a new stream */
    private nextStreamID;
    /** Primary stream mapping, streamID => stream */
    private readonly _streams;
    /** The next ping id to be used when pinging */
    private nextPingID;
    /** Tracking info for the currently active ping */
    private activePing?;
    /** Round trip time */
    private rtt;
    /** True if client, false if server */
    private readonly client;
    private localGoAway?;
    private remoteGoAway?;
    /** Number of tracked inbound streams */
    private numInboundStreams;
    /** Number of tracked outbound streams */
    private numOutboundStreams;
    private readonly onIncomingStream?;
    private readonly onStreamEnd?;
    constructor(init: YamuxMuxerInit);
    get streams(): YamuxStream[];
    newStream(name?: string | undefined): YamuxStream;
    /**
     * Initiate a ping and wait for a response
     *
     * Note: only a single ping will be initiated at a time.
     * If a ping is already in progress, a new ping will not be initiated.
     *
     * @returns the round-trip-time in milliseconds
     */
    ping(): Promise<number>;
    /**
     * Get the ping round trip time
     *
     * Note: Will return 0 if no successful ping has yet been completed
     *
     * @returns the round-trip-time in milliseconds
     */
    getRTT(): number;
    /**
     * Close the muxer
     */
    close(options?: CloseOptions): Promise<void>;
    abort(err: Error, reason?: GoAwayCode): void;
    isClosed(): boolean;
    /**
     * Called when either the local or remote shuts down the muxer
     */
    private _closeMuxer;
    /** Create a new stream */
    private _newStream;
    /**
     * closeStream is used to close a stream once both sides have
     * issued a close.
     */
    private closeStream;
    private keepAliveLoop;
    private handleFrame;
    private handlePing;
    private handlePingResponse;
    private handleGoAway;
    private handleStreamMessage;
    private incomingStream;
    private sendFrame;
    private sendPing;
    private sendGoAway;
}
//# sourceMappingURL=muxer.d.ts.map