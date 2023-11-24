import { TypedEventEmitter } from '@libp2p/interface/events';
import type { TCPCreateListenerOptions } from './index.js';
import type { ComponentLogger } from '@libp2p/interface';
import type { Connection } from '@libp2p/interface/connection';
import type { CounterGroup, MetricGroup, Metrics } from '@libp2p/interface/metrics';
import type { Listener, ListenerEvents, Upgrader } from '@libp2p/interface/transport';
import type { Multiaddr } from '@multiformats/multiaddr';
export interface CloseServerOnMaxConnectionsOpts {
    /** Server listens once connection count is less than `listenBelow` */
    listenBelow: number;
    /** Close server once connection count is greater than or equal to `closeAbove` */
    closeAbove: number;
    onListenError?(err: Error): void;
}
interface Context extends TCPCreateListenerOptions {
    handler?(conn: Connection): void;
    upgrader: Upgrader;
    socketInactivityTimeout?: number;
    socketCloseTimeout?: number;
    maxConnections?: number;
    backlog?: number;
    metrics?: Metrics;
    closeServerOnMaxConnections?: CloseServerOnMaxConnectionsOpts;
    logger: ComponentLogger;
}
export interface TCPListenerMetrics {
    status: MetricGroup;
    errors: CounterGroup;
    events: CounterGroup;
}
export declare class TCPListener extends TypedEventEmitter<ListenerEvents> implements Listener {
    private readonly context;
    private readonly server;
    /** Keep track of open connections to destroy in case of timeout */
    private readonly connections;
    private status;
    private metrics?;
    private addr;
    private readonly log;
    constructor(context: Context);
    private onSocket;
    getAddrs(): Multiaddr[];
    listen(ma: Multiaddr): Promise<void>;
    close(): Promise<void>;
    /**
     * Can resume a stopped or start an inert server
     */
    private resume;
    private pause;
}
export {};
//# sourceMappingURL=listener.d.ts.map