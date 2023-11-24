import type { AbortOptions } from '@libp2p/interface';
import type { ContentRouting } from '@libp2p/interface/content-routing';
import type { PeerInfo } from '@libp2p/interface/peer-info';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { Startable } from '@libp2p/interface/startable';
import type { CID } from 'multiformats/cid';
export interface CompoundContentRoutingInit {
    routers: ContentRouting[];
}
export interface CompoundContentRoutingComponents {
    peerStore: PeerStore;
}
export declare class CompoundContentRouting implements ContentRouting, Startable {
    private readonly routers;
    private started;
    private readonly components;
    constructor(components: CompoundContentRoutingComponents, init: CompoundContentRoutingInit);
    isStarted(): boolean;
    start(): Promise<void>;
    stop(): Promise<void>;
    /**
     * Iterates over all content routers in parallel to find providers of the given key
     */
    findProviders(key: CID, options?: AbortOptions): AsyncIterable<PeerInfo>;
    /**
     * Iterates over all content routers in parallel to notify it is
     * a provider of the given key
     */
    provide(key: CID, options?: AbortOptions): Promise<void>;
    /**
     * Store the given key/value pair in the available content routings
     */
    put(key: Uint8Array, value: Uint8Array, options?: AbortOptions): Promise<void>;
    /**
     * Get the value to the given key.
     * Times out after 1 minute by default.
     */
    get(key: Uint8Array, options?: AbortOptions): Promise<Uint8Array>;
}
//# sourceMappingURL=index.d.ts.map