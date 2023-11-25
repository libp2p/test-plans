import { type ContentRouting } from '@libp2p/interface/content-routing';
import { TypedEventEmitter } from '@libp2p/interface/events';
import { type PeerRouting } from '@libp2p/interface/peer-routing';
import { type Multiaddr } from '@multiformats/multiaddr';
import type { Components } from './components.js';
import type { Libp2p, Libp2pInit, Libp2pOptions } from './index.js';
import type { Libp2pEvents, PendingDial, ServiceMap, AbortOptions, ComponentLogger } from '@libp2p/interface';
import type { Connection, NewStreamOptions, Stream } from '@libp2p/interface/connection';
import type { Metrics } from '@libp2p/interface/metrics';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { Topology } from '@libp2p/interface/topology';
import type { StreamHandler, StreamHandlerOptions } from '@libp2p/interface-internal/registrar';
export declare class Libp2pNode<T extends ServiceMap = Record<string, unknown>> extends TypedEventEmitter<Libp2pEvents> implements Libp2p<T> {
    #private;
    peerId: PeerId;
    peerStore: PeerStore;
    contentRouting: ContentRouting;
    peerRouting: PeerRouting;
    metrics?: Metrics;
    services: T;
    logger: ComponentLogger;
    components: Components;
    private readonly log;
    constructor(init: Libp2pInit<T>);
    private configureComponent;
    /**
     * Starts the libp2p node and all its subsystems
     */
    start(): Promise<void>;
    /**
     * Stop the libp2p node by closing its listeners and open connections
     */
    stop(): Promise<void>;
    isStarted(): boolean;
    getConnections(peerId?: PeerId): Connection[];
    getDialQueue(): PendingDial[];
    getPeers(): PeerId[];
    dial(peer: PeerId | Multiaddr | Multiaddr[], options?: AbortOptions): Promise<Connection>;
    dialProtocol(peer: PeerId | Multiaddr | Multiaddr[], protocols: string | string[], options?: NewStreamOptions): Promise<Stream>;
    getMultiaddrs(): Multiaddr[];
    getProtocols(): string[];
    hangUp(peer: PeerId | Multiaddr, options?: AbortOptions): Promise<void>;
    /**
     * Get the public key for the given peer id
     */
    getPublicKey(peer: PeerId, options?: AbortOptions): Promise<Uint8Array>;
    handle(protocols: string | string[], handler: StreamHandler, options?: StreamHandlerOptions): Promise<void>;
    unhandle(protocols: string[] | string): Promise<void>;
    register(protocol: string, topology: Topology): Promise<string>;
    unregister(id: string): void;
}
/**
 * Returns a new Libp2pNode instance - this exposes more of the internals than the
 * libp2p interface and is useful for testing and debugging.
 */
export declare function createLibp2pNode<T extends ServiceMap = Record<string, unknown>>(options: Libp2pOptions<T>): Promise<Libp2pNode<T>>;
//# sourceMappingURL=libp2p.d.ts.map