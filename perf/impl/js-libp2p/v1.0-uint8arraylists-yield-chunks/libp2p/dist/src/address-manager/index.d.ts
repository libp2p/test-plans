import type { ComponentLogger, Libp2pEvents } from '@libp2p/interface';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { TransportManager } from '@libp2p/interface-internal/transport-manager';
import type { Multiaddr } from '@multiformats/multiaddr';
export interface AddressManagerInit {
    /**
     * Pass an function in this field to override the list of addresses
     * that are announced to the network
     */
    announceFilter?: AddressFilter;
    /**
     * list of multiaddrs string representation to listen
     */
    listen?: string[];
    /**
     * list of multiaddrs string representation to announce
     */
    announce?: string[];
    /**
     * list of multiaddrs string representation to never announce
     */
    noAnnounce?: string[];
}
export interface DefaultAddressManagerComponents {
    peerId: PeerId;
    transportManager: TransportManager;
    peerStore: PeerStore;
    events: TypedEventTarget<Libp2pEvents>;
    logger: ComponentLogger;
}
/**
 * A function that takes a list of multiaddrs and returns a list
 * to announce
 */
export interface AddressFilter {
    (addrs: Multiaddr[]): Multiaddr[];
}
export declare class DefaultAddressManager {
    private readonly log;
    private readonly components;
    private readonly listen;
    private readonly announce;
    private readonly observed;
    private readonly announceFilter;
    /**
     * Responsible for managing the peer addresses.
     * Peers can specify their listen and announce addresses.
     * The listen addresses will be used by the libp2p transports to listen for new connections,
     * while the announce addresses will be used for the peer addresses' to other peers in the network.
     */
    constructor(components: DefaultAddressManagerComponents, init?: AddressManagerInit);
    _updatePeerStoreAddresses(): void;
    /**
     * Get peer listen multiaddrs
     */
    getListenAddrs(): Multiaddr[];
    /**
     * Get peer announcing multiaddrs
     */
    getAnnounceAddrs(): Multiaddr[];
    /**
     * Get observed multiaddrs
     */
    getObservedAddrs(): Multiaddr[];
    /**
     * Add peer observed addresses
     */
    addObservedAddr(addr: Multiaddr): void;
    confirmObservedAddr(addr: Multiaddr): void;
    removeObservedAddr(addr: Multiaddr): void;
    getAddresses(): Multiaddr[];
}
//# sourceMappingURL=index.d.ts.map