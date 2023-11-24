import type { Libp2pEvents, ComponentLogger } from '@libp2p/interface';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { ConnectionManager } from '@libp2p/interface-internal/connection-manager';
import type { Multiaddr } from '@multiformats/multiaddr';
interface ConnectionPrunerInit {
    maxConnections?: number;
    allow?: Multiaddr[];
}
interface ConnectionPrunerComponents {
    connectionManager: ConnectionManager;
    peerStore: PeerStore;
    events: TypedEventTarget<Libp2pEvents>;
    logger: ComponentLogger;
}
/**
 * If we go over the max connections limit, choose some connections to close
 */
export declare class ConnectionPruner {
    private readonly maxConnections;
    private readonly connectionManager;
    private readonly peerStore;
    private readonly allow;
    private readonly events;
    private readonly log;
    constructor(components: ConnectionPrunerComponents, init?: ConnectionPrunerInit);
    /**
     * If we have more connections than our maximum, select some excess connections
     * to prune based on peer value
     */
    maybePruneConnections(): Promise<void>;
}
export {};
//# sourceMappingURL=connection-pruner.d.ts.map