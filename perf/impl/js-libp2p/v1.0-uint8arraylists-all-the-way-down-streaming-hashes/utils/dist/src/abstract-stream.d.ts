import { Uint8ArrayList } from 'uint8arraylist';
import type { AbortOptions } from '@libp2p/interface';
import type { Direction, ReadStatus, Stream, StreamStatus, StreamTimeline, WriteStatus } from '@libp2p/interface/connection';
import type { Logger } from '@libp2p/logger';
import type { Source } from 'it-stream-types';
export interface AbstractStreamInit {
    /**
     * A unique identifier for this stream
     */
    id: string;
    /**
     * The stream direction
     */
    direction: Direction;
    /**
     * A Logger implementation used to log stream-specific information
     */
    log: Logger;
    /**
     * User specific stream metadata
     */
    metadata?: Record<string, unknown>;
    /**
     * Invoked when the stream ends
     */
    onEnd?(err?: Error | undefined): void;
    /**
     * Invoked when the readable end of the stream is closed
     */
    onCloseRead?(): void;
    /**
     * Invoked when the writable end of the stream is closed
     */
    onCloseWrite?(): void;
    /**
     * Invoked when the the stream has been reset by the remote
     */
    onReset?(): void;
    /**
     * Invoked when the the stream has errored
     */
    onAbort?(err: Error): void;
    /**
     * How long to wait in ms for stream data to be written to the underlying
     * connection when closing the writable end of the stream. (default: 500)
     */
    closeTimeout?: number;
    /**
     * After the stream sink has closed, a limit on how long it takes to send
     * a close-write message to the remote peer.
     */
    sendCloseWriteTimeout?: number;
}
export declare abstract class AbstractStream implements Stream {
    id: string;
    direction: Direction;
    timeline: StreamTimeline;
    protocol?: string;
    metadata: Record<string, unknown>;
    source: AsyncGenerator<Uint8ArrayList, void, unknown>;
    status: StreamStatus;
    readStatus: ReadStatus;
    writeStatus: WriteStatus;
    readonly log: Logger;
    private readonly sinkController;
    private readonly sinkEnd;
    private readonly closed;
    private endErr;
    private readonly streamSource;
    private readonly onEnd?;
    private readonly onCloseRead?;
    private readonly onCloseWrite?;
    private readonly onReset?;
    private readonly onAbort?;
    private readonly sendCloseWriteTimeout;
    constructor(init: AbstractStreamInit);
    sink(source: Source<Uint8ArrayList | Uint8Array>): Promise<void>;
    protected onSourceEnd(err?: Error): void;
    protected onSinkEnd(err?: Error): void;
    close(options?: AbortOptions): Promise<void>;
    closeRead(options?: AbortOptions): Promise<void>;
    closeWrite(options?: AbortOptions): Promise<void>;
    /**
     * Close immediately for reading and writing and send a reset message (local
     * error)
     */
    abort(err: Error): void;
    /**
     * Receive a reset message - close immediately for reading and writing (remote
     * error)
     */
    reset(): void;
    _closeSinkAndSource(err?: Error): void;
    _closeSink(err?: Error): void;
    _closeSource(err?: Error): void;
    /**
     * The remote closed for writing so we should expect to receive no more
     * messages
     */
    remoteCloseWrite(): void;
    /**
     * The remote closed for reading so we should not send any more
     * messages
     */
    remoteCloseRead(): void;
    /**
     * The underlying muxer has closed, no more messages can be sent or will
     * be received, close immediately to free up resources
     */
    destroy(): void;
    /**
     * When an extending class reads data from it's implementation-specific source,
     * call this method to allow the stream consumer to read the data.
     */
    sourcePush(data: Uint8ArrayList): void;
    /**
     * Returns the amount of unread data - can be used to prevent large amounts of
     * data building up when the stream consumer is too slow.
     */
    sourceReadableLength(): number;
    /**
     * Send a message to the remote muxer informing them a new stream is being
     * opened
     */
    abstract sendNewStream(options?: AbortOptions): void | Promise<void>;
    /**
     * Send a data message to the remote muxer
     */
    abstract sendData(buf: Uint8ArrayList, options?: AbortOptions): void | Promise<void>;
    /**
     * Send a reset message to the remote muxer
     */
    abstract sendReset(options?: AbortOptions): void | Promise<void>;
    /**
     * Send a message to the remote muxer, informing them no more data messages
     * will be sent by this end of the stream
     */
    abstract sendCloseWrite(options?: AbortOptions): void | Promise<void>;
    /**
     * Send a message to the remote muxer, informing them no more data messages
     * will be read by this end of the stream
     */
    abstract sendCloseRead(options?: AbortOptions): void | Promise<void>;
}
//# sourceMappingURL=abstract-stream.d.ts.map