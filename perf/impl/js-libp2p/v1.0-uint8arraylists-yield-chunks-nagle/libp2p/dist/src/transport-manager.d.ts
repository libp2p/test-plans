import { FaultTolerance } from '@libp2p/interface/transport';
import type { Libp2pEvents, AbortOptions, ComponentLogger } from '@libp2p/interface';
import type { Connection } from '@libp2p/interface/connection';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { Metrics } from '@libp2p/interface/metrics';
import type { Startable } from '@libp2p/interface/startable';
import type { Listener, Transport, Upgrader } from '@libp2p/interface/transport';
import type { AddressManager } from '@libp2p/interface-internal/address-manager';
import type { TransportManager } from '@libp2p/interface-internal/transport-manager';
import type { Multiaddr } from '@multiformats/multiaddr';
export interface TransportManagerInit {
    faultTolerance?: FaultTolerance;
}
export interface DefaultTransportManagerComponents {
    metrics?: Metrics;
    addressManager: AddressManager;
    upgrader: Upgrader;
    events: TypedEventTarget<Libp2pEvents>;
    logger: ComponentLogger;
}
export declare class DefaultTransportManager implements TransportManager, Startable {
    private readonly log;
    private readonly components;
    private readonly transports;
    private readonly listeners;
    private readonly faultTolerance;
    private started;
    constructor(components: DefaultTransportManagerComponents, init?: TransportManagerInit);
    /**
     * Adds a `Transport` to the manager
     */
    add(transport: Transport): void;
    isStarted(): boolean;
    start(): void;
    afterStart(): Promise<void>;
    /**
     * Stops all listeners
     */
    stop(): Promise<void>;
    /**
     * Dials the given Multiaddr over it's supported transport
     */
    dial(ma: Multiaddr, options?: AbortOptions): Promise<Connection>;
    /**
     * Returns all Multiaddr's the listeners are using
     */
    getAddrs(): Multiaddr[];
    /**
     * Returns all the transports instances
     */
    getTransports(): Transport[];
    /**
     * Returns all the listener instances
     */
    getListeners(): Listener[];
    /**
     * Finds a transport that matches the given Multiaddr
     */
    transportForMultiaddr(ma: Multiaddr): Transport | undefined;
    /**
     * Starts listeners for each listen Multiaddr
     */
    listen(addrs: Multiaddr[]): Promise<void>;
    /**
     * Removes the given transport from the manager.
     * If a transport has any running listeners, they will be closed.
     */
    remove(key: string): Promise<void>;
    /**
     * Removes all transports from the manager.
     * If any listeners are running, they will be closed.
     *
     * @async
     */
    removeAll(): Promise<void>;
}
//# sourceMappingURL=transport-manager.d.ts.map