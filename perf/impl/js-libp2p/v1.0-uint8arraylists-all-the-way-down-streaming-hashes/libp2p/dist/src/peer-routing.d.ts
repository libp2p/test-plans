import type { AbortOptions } from '@libp2p/interface';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerInfo } from '@libp2p/interface/peer-info';
import type { PeerRouting } from '@libp2p/interface/peer-routing';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { ComponentLogger } from '@libp2p/logger';
export interface PeerRoutingInit {
    routers?: PeerRouting[];
}
export interface DefaultPeerRoutingComponents {
    peerId: PeerId;
    peerStore: PeerStore;
    logger: ComponentLogger;
}
export declare class DefaultPeerRouting implements PeerRouting {
    private readonly log;
    private readonly peerId;
    private readonly peerStore;
    private readonly routers;
    constructor(components: DefaultPeerRoutingComponents, init: PeerRoutingInit);
    /**
     * Iterates over all peer routers in parallel to find the given peer
     */
    findPeer(id: PeerId, options?: AbortOptions): Promise<PeerInfo>;
    /**
     * Attempt to find the closest peers on the network to the given key
     */
    getClosestPeers(key: Uint8Array, options?: AbortOptions): AsyncIterable<PeerInfo>;
}
//# sourceMappingURL=peer-routing.d.ts.map