import type { IdentifyResult, Libp2pEvents, PeerUpdate } from '@libp2p/interface';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { Topology } from '@libp2p/interface/topology';
import type { ConnectionManager } from '@libp2p/interface-internal/connection-manager';
import type { StreamHandlerOptions, StreamHandlerRecord, Registrar, StreamHandler } from '@libp2p/interface-internal/registrar';
import type { ComponentLogger } from '@libp2p/logger';
export declare const DEFAULT_MAX_INBOUND_STREAMS = 32;
export declare const DEFAULT_MAX_OUTBOUND_STREAMS = 64;
export interface RegistrarComponents {
    peerId: PeerId;
    connectionManager: ConnectionManager;
    peerStore: PeerStore;
    events: TypedEventTarget<Libp2pEvents>;
    logger: ComponentLogger;
}
/**
 * Responsible for notifying registered protocols of events in the network.
 */
export declare class DefaultRegistrar implements Registrar {
    private readonly log;
    private readonly topologies;
    private readonly handlers;
    private readonly components;
    constructor(components: RegistrarComponents);
    getProtocols(): string[];
    getHandler(protocol: string): StreamHandlerRecord;
    getTopologies(protocol: string): Topology[];
    /**
     * Registers the `handler` for each protocol
     */
    handle(protocol: string, handler: StreamHandler, opts?: StreamHandlerOptions): Promise<void>;
    /**
     * Removes the handler for each protocol. The protocol
     * will no longer be supported on streams.
     */
    unhandle(protocols: string | string[]): Promise<void>;
    /**
     * Register handlers for a set of multicodecs given
     */
    register(protocol: string, topology: Topology): Promise<string>;
    /**
     * Unregister topology
     */
    unregister(id: string): void;
    /**
     * Remove a disconnected peer from the record
     */
    _onDisconnect(evt: CustomEvent<PeerId>): void;
    /**
     * When a peer is updated, if they have removed supported protocols notify any
     * topologies interested in the removed protocols.
     */
    _onPeerUpdate(evt: CustomEvent<PeerUpdate>): void;
    /**
     * After identify has completed and we have received the list of supported
     * protocols, notify any topologies interested in those protocols.
     */
    _onPeerIdentify(evt: CustomEvent<IdentifyResult>): void;
}
//# sourceMappingURL=registrar.d.ts.map