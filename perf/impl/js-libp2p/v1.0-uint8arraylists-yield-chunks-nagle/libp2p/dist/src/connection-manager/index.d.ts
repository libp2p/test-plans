import { PeerMap } from '@libp2p/peer-collections';
import { type Multiaddr, type Resolver } from '@multiformats/multiaddr';
import { AutoDial } from './auto-dial.js';
import { ConnectionPruner } from './connection-pruner.js';
import { DialQueue } from './dial-queue.js';
import type { PendingDial, AddressSorter, Libp2pEvents, AbortOptions, ComponentLogger } from '@libp2p/interface';
import type { Connection, MultiaddrConnection } from '@libp2p/interface/connection';
import type { ConnectionGater } from '@libp2p/interface/connection-gater';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { Metrics } from '@libp2p/interface/metrics';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { Startable } from '@libp2p/interface/startable';
import type { ConnectionManager, OpenConnectionOptions } from '@libp2p/interface-internal/connection-manager';
import type { TransportManager } from '@libp2p/interface-internal/transport-manager';
export interface ConnectionManagerInit {
    /**
     * The maximum number of connections libp2p is willing to have before it starts
     * pruning connections to reduce resource usage. (default: 300, 100 in browsers)
     */
    maxConnections?: number;
    /**
     * The minimum number of connections below which libp2p will start to dial peers
     * from the peer book. Setting this to 0 effectively disables this behaviour.
     * (default: 50, 5 in browsers)
     */
    minConnections?: number;
    /**
     * How long to wait between attempting to keep our number of concurrent connections
     * above minConnections (default: 5000)
     */
    autoDialInterval?: number;
    /**
     * When dialling peers from the peer book to keep the number of open connections
     * above `minConnections`, add dials for this many peers to the dial queue
     * at once. (default: 25)
     */
    autoDialConcurrency?: number;
    /**
     * To allow user dials to take priority over auto dials, use this value as the
     * dial priority. (default: 0)
     */
    autoDialPriority?: number;
    /**
     * Limit the maximum number of peers to dial when trying to keep the number of
     * open connections above `minConnections`. (default: 100)
     */
    autoDialMaxQueueLength?: number;
    /**
     * When we've failed to dial a peer, do not autodial them again within this
     * number of ms. (default: 1 minute, 7 minutes in browsers)
     */
    autoDialPeerRetryThreshold?: number;
    /**
     * Newly discovered peers may be auto-dialed to increase the number of open
     * connections, but they can be discovered in quick succession so add a small
     * delay before attempting to dial them in case more peers have been
     * discovered. (default: 10ms)
     */
    autoDialDiscoveredPeersDebounce?: number;
    /**
     * Sort the known addresses of a peer before trying to dial, By default public
     * addresses will be dialled before private (e.g. loopback or LAN) addresses.
     */
    addressSorter?: AddressSorter;
    /**
     * The maximum number of dials across all peers to execute in parallel.
     * (default: 100, 50 in browsers)
     */
    maxParallelDials?: number;
    /**
     * Maximum number of addresses allowed for a given peer - if a peer has more
     * addresses than this then the dial will fail. (default: 25)
     */
    maxPeerAddrsToDial?: number;
    /**
     * How long a dial attempt is allowed to take, including DNS resolution
     * of the multiaddr, opening a socket and upgrading it to a Connection.
     */
    dialTimeout?: number;
    /**
     * When a new inbound connection is opened, the upgrade process (e.g. protect,
     * encrypt, multiplex etc) must complete within this number of ms. (default: 30s)
     */
    inboundUpgradeTimeout?: number;
    /**
     * Multiaddr resolvers to use when dialling
     */
    resolvers?: Record<string, Resolver>;
    /**
     * A list of multiaddrs that will always be allowed (except if they are in the
     * deny list) to open connections to this node even if we've reached maxConnections
     */
    allow?: string[];
    /**
     * A list of multiaddrs that will never be allowed to open connections to
     * this node under any circumstances
     */
    deny?: string[];
    /**
     * If more than this many connections are opened per second by a single
     * host, reject subsequent connections. (default: 5)
     */
    inboundConnectionThreshold?: number;
    /**
     * The maximum number of parallel incoming connections allowed that have yet to
     * complete the connection upgrade - e.g. choosing connection encryption, muxer, etc.
     * (default: 10)
     */
    maxIncomingPendingConnections?: number;
}
export interface DefaultConnectionManagerComponents {
    peerId: PeerId;
    metrics?: Metrics;
    peerStore: PeerStore;
    transportManager: TransportManager;
    connectionGater: ConnectionGater;
    events: TypedEventTarget<Libp2pEvents>;
    logger: ComponentLogger;
}
/**
 * Responsible for managing known connections.
 */
export declare class DefaultConnectionManager implements ConnectionManager, Startable {
    private started;
    private readonly connections;
    private readonly allow;
    private readonly deny;
    private readonly maxIncomingPendingConnections;
    private incomingPendingConnections;
    private readonly maxConnections;
    readonly dialQueue: DialQueue;
    readonly autoDial: AutoDial;
    readonly connectionPruner: ConnectionPruner;
    private readonly inboundConnectionRateLimiter;
    private readonly peerStore;
    private readonly metrics?;
    private readonly events;
    private readonly log;
    constructor(components: DefaultConnectionManagerComponents, init?: ConnectionManagerInit);
    isStarted(): boolean;
    /**
     * Starts the Connection Manager. If Metrics are not enabled on libp2p
     * only event loop and connection limits will be monitored.
     */
    start(): Promise<void>;
    afterStart(): Promise<void>;
    /**
     * Stops the Connection Manager
     */
    stop(): Promise<void>;
    onConnect(evt: CustomEvent<Connection>): void;
    /**
     * Tracks the incoming connection and check the connection limit
     */
    _onConnect(evt: CustomEvent<Connection>): Promise<void>;
    /**
     * Removes the connection from tracking
     */
    onDisconnect(evt: CustomEvent<Connection>): void;
    getConnections(peerId?: PeerId): Connection[];
    getConnectionsMap(): PeerMap<Connection[]>;
    openConnection(peerIdOrMultiaddr: PeerId | Multiaddr | Multiaddr[], options?: OpenConnectionOptions): Promise<Connection>;
    closeConnections(peerId: PeerId, options?: AbortOptions): Promise<void>;
    acceptIncomingConnection(maConn: MultiaddrConnection): Promise<boolean>;
    afterUpgradeInbound(): void;
    getDialQueue(): PendingDial[];
}
//# sourceMappingURL=index.d.ts.map