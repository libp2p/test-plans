import type { Libp2pEvents, ComponentLogger } from '@libp2p/interface';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { Startable } from '@libp2p/interface/startable';
import type { ConnectionManager } from '@libp2p/interface-internal/connection-manager';
interface AutoDialInit {
    minConnections?: number;
    maxQueueLength?: number;
    autoDialConcurrency?: number;
    autoDialPriority?: number;
    autoDialInterval?: number;
    autoDialPeerRetryThreshold?: number;
    autoDialDiscoveredPeersDebounce?: number;
}
interface AutoDialComponents {
    connectionManager: ConnectionManager;
    peerStore: PeerStore;
    events: TypedEventTarget<Libp2pEvents>;
    logger: ComponentLogger;
}
export declare class AutoDial implements Startable {
    private readonly connectionManager;
    private readonly peerStore;
    private readonly queue;
    private readonly minConnections;
    private readonly autoDialPriority;
    private readonly autoDialIntervalMs;
    private readonly autoDialMaxQueueLength;
    private readonly autoDialPeerRetryThresholdMs;
    private readonly autoDialDiscoveredPeersDebounce;
    private autoDialInterval?;
    private started;
    private running;
    private readonly log;
    /**
     * Proactively tries to connect to known peers stored in the PeerStore.
     * It will keep the number of connections below the upper limit and sort
     * the peers to connect based on whether we know their keys and protocols.
     */
    constructor(components: AutoDialComponents, init: AutoDialInit);
    isStarted(): boolean;
    start(): void;
    afterStart(): void;
    stop(): void;
    autoDial(): Promise<void>;
}
export {};
//# sourceMappingURL=auto-dial.d.ts.map