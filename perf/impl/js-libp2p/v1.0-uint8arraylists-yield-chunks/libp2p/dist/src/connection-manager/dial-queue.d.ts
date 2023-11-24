import { PeerMap } from '@libp2p/peer-collections';
import { type Multiaddr, type Resolver } from '@multiformats/multiaddr';
import PQueue from 'p-queue';
import type { AddressSorter, AbortOptions, PendingDial, ComponentLogger } from '@libp2p/interface';
import type { Connection } from '@libp2p/interface/connection';
import type { ConnectionGater } from '@libp2p/interface/connection-gater';
import type { Metrics } from '@libp2p/interface/metrics';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { TransportManager } from '@libp2p/interface-internal/transport-manager';
export interface PendingDialTarget {
    resolve(value: any): void;
    reject(err: Error): void;
}
export interface DialOptions extends AbortOptions {
    priority?: number;
    force?: boolean;
}
interface PendingDialInternal extends PendingDial {
    promise: Promise<Connection>;
}
interface DialerInit {
    addressSorter?: AddressSorter;
    maxParallelDials?: number;
    maxPeerAddrsToDial?: number;
    dialTimeout?: number;
    resolvers?: Record<string, Resolver>;
    connections?: PeerMap<Connection[]>;
}
interface DialQueueComponents {
    peerId: PeerId;
    metrics?: Metrics;
    peerStore: PeerStore;
    transportManager: TransportManager;
    connectionGater: ConnectionGater;
    logger: ComponentLogger;
}
export declare class DialQueue {
    pendingDials: PendingDialInternal[];
    queue: PQueue;
    private readonly peerId;
    private readonly peerStore;
    private readonly connectionGater;
    private readonly transportManager;
    private readonly addressSorter;
    private readonly maxPeerAddrsToDial;
    private readonly dialTimeout;
    private readonly inProgressDialCount?;
    private readonly pendingDialCount?;
    private readonly shutDownController;
    private readonly connections;
    private readonly log;
    constructor(components: DialQueueComponents, init?: DialerInit);
    /**
     * Clears any pending dials
     */
    stop(): void;
    /**
     * Connects to a given peer, multiaddr or list of multiaddrs.
     *
     * If a peer is passed, all known multiaddrs will be tried. If a multiaddr or
     * multiaddrs are passed only those will be dialled.
     *
     * Where a list of multiaddrs is passed, if any contain a peer id then all
     * multiaddrs in the list must contain the same peer id.
     *
     * The dial to the first address that is successfully able to upgrade a connection
     * will be used, all other dials will be aborted when that happens.
     */
    dial(peerIdOrMultiaddr: PeerId | Multiaddr | Multiaddr[], options?: DialOptions): Promise<Connection>;
    private createDialAbortControllers;
    private calculateMultiaddrs;
    private performDial;
}
export {};
//# sourceMappingURL=dial-queue.d.ts.map