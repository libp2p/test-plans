import { symbol } from '@libp2p/interface/connection';
import type { AbortOptions, Logger, ComponentLogger } from '@libp2p/interface';
import type { Direction, Connection, Stream, ConnectionTimeline, ConnectionStatus, NewStreamOptions } from '@libp2p/interface/connection';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { Multiaddr } from '@multiformats/multiaddr';
interface ConnectionInit {
    remoteAddr: Multiaddr;
    remotePeer: PeerId;
    newStream(protocols: string[], options?: AbortOptions): Promise<Stream>;
    close(options?: AbortOptions): Promise<void>;
    abort(err: Error): void;
    getStreams(): Stream[];
    status: ConnectionStatus;
    direction: Direction;
    timeline: ConnectionTimeline;
    multiplexer?: string;
    encryption?: string;
    transient?: boolean;
    logger: ComponentLogger;
}
/**
 * An implementation of the js-libp2p connection.
 * Any libp2p transport should use an upgrader to return this connection.
 */
export declare class ConnectionImpl implements Connection {
    /**
     * Connection identifier.
     */
    readonly id: string;
    /**
     * Observed multiaddr of the remote peer
     */
    readonly remoteAddr: Multiaddr;
    /**
     * Remote peer id
     */
    readonly remotePeer: PeerId;
    direction: Direction;
    timeline: ConnectionTimeline;
    multiplexer?: string;
    encryption?: string;
    status: ConnectionStatus;
    transient: boolean;
    readonly log: Logger;
    /**
     * User provided tags
     *
     */
    tags: string[];
    /**
     * Reference to the new stream function of the multiplexer
     */
    private readonly _newStream;
    /**
     * Reference to the close function of the raw connection
     */
    private readonly _close;
    private readonly _abort;
    /**
     * Reference to the getStreams function of the muxer
     */
    private readonly _getStreams;
    /**
     * An implementation of the js-libp2p connection.
     * Any libp2p transport should use an upgrader to return this connection.
     */
    constructor(init: ConnectionInit);
    readonly [Symbol.toStringTag] = "Connection";
    readonly [symbol] = true;
    /**
     * Get all the streams of the muxer
     */
    get streams(): Stream[];
    /**
     * Create a new stream from this connection
     */
    newStream(protocols: string | string[], options?: NewStreamOptions): Promise<Stream>;
    /**
     * Close the connection
     */
    close(options?: AbortOptions): Promise<void>;
    abort(err: Error): void;
}
export declare function createConnection(init: ConnectionInit): Connection;
export {};
//# sourceMappingURL=index.d.ts.map