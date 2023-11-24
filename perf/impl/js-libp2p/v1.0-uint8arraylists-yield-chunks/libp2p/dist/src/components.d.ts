import { type Startable } from '@libp2p/interface/startable';
import type { Libp2pEvents, ComponentLogger, NodeInfo } from '@libp2p/interface';
import type { ConnectionProtector } from '@libp2p/interface/connection';
import type { ConnectionGater } from '@libp2p/interface/connection-gater';
import type { ContentRouting } from '@libp2p/interface/content-routing';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { Metrics } from '@libp2p/interface/metrics';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerRouting } from '@libp2p/interface/peer-routing';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { Upgrader } from '@libp2p/interface/transport';
import type { AddressManager } from '@libp2p/interface-internal/address-manager';
import type { ConnectionManager } from '@libp2p/interface-internal/connection-manager';
import type { Registrar } from '@libp2p/interface-internal/registrar';
import type { TransportManager } from '@libp2p/interface-internal/transport-manager';
import type { Datastore } from 'interface-datastore';
export interface Components extends Record<string, any>, Startable {
    peerId: PeerId;
    nodeInfo: NodeInfo;
    logger: ComponentLogger;
    events: TypedEventTarget<Libp2pEvents>;
    addressManager: AddressManager;
    peerStore: PeerStore;
    upgrader: Upgrader;
    registrar: Registrar;
    connectionManager: ConnectionManager;
    transportManager: TransportManager;
    connectionGater: ConnectionGater;
    contentRouting: ContentRouting;
    peerRouting: PeerRouting;
    datastore: Datastore;
    connectionProtector?: ConnectionProtector;
    metrics?: Metrics;
}
export interface ComponentsInit {
    peerId?: PeerId;
    nodeInfo?: NodeInfo;
    logger?: ComponentLogger;
    events?: TypedEventTarget<Libp2pEvents>;
    addressManager?: AddressManager;
    peerStore?: PeerStore;
    upgrader?: Upgrader;
    metrics?: Metrics;
    registrar?: Registrar;
    connectionManager?: ConnectionManager;
    transportManager?: TransportManager;
    connectionGater?: ConnectionGater;
    contentRouting?: ContentRouting;
    peerRouting?: PeerRouting;
    datastore?: Datastore;
    connectionProtector?: ConnectionProtector;
}
export declare function defaultComponents(init?: ComponentsInit): Components;
//# sourceMappingURL=components.d.ts.map