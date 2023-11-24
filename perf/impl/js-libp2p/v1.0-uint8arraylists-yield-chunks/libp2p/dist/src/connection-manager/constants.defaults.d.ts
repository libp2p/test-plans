/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#dialTimeout
 */
export declare const DIAL_TIMEOUT = 30000;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#inboundUpgradeTimeout
 */
export declare const INBOUND_UPGRADE_TIMEOUT = 30000;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#maxPeerAddrsToDial
 */
export declare const MAX_PEER_ADDRS_TO_DIAL = 25;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#autoDialInterval
 */
export declare const AUTO_DIAL_INTERVAL = 5000;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#autoDialConcurrency
 */
export declare const AUTO_DIAL_CONCURRENCY = 25;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#autoDialPriority
 */
export declare const AUTO_DIAL_PRIORITY = 0;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#autoDialMaxQueueLength
 */
export declare const AUTO_DIAL_MAX_QUEUE_LENGTH = 100;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/libp2p.index.unknown.ConnectionManagerInit.html#autoDialDiscoveredPeersDebounce
 */
export declare const AUTO_DIAL_DISCOVERED_PEERS_DEBOUNCE = 10;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#inboundConnectionThreshold
 */
export declare const INBOUND_CONNECTION_THRESHOLD = 5;
/**
 * @see https://libp2p.github.io/js-libp2p/interfaces/index._internal_.ConnectionManagerConfig.html#maxIncomingPendingConnections
 */
export declare const MAX_INCOMING_PENDING_CONNECTIONS = 10;
/**
 * Store as part of the peer store metadata for a given peer, the value for this
 * key is a timestamp of the last time a dial attempted failed with the relevant
 * peer stored as a string.
 *
 * Used to insure we do not endlessly try to auto dial peers we have recently
 * failed to dial.
 */
export declare const LAST_DIAL_FAILURE_KEY = "last-dial-failure";
//# sourceMappingURL=constants.defaults.d.ts.map