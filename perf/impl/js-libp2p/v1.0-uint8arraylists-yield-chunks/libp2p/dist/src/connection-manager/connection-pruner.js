import { PeerMap } from '@libp2p/peer-collections';
import { MAX_CONNECTIONS } from './constants.js';
const defaultOptions = {
    maxConnections: MAX_CONNECTIONS,
    allow: []
};
/**
 * If we go over the max connections limit, choose some connections to close
 */
export class ConnectionPruner {
    maxConnections;
    connectionManager;
    peerStore;
    allow;
    events;
    log;
    constructor(components, init = {}) {
        this.maxConnections = init.maxConnections ?? defaultOptions.maxConnections;
        this.allow = init.allow ?? defaultOptions.allow;
        this.connectionManager = components.connectionManager;
        this.peerStore = components.peerStore;
        this.events = components.events;
        this.log = components.logger.forComponent('libp2p:connection-manager:connection-pruner');
        // check the max connection limit whenever a peer connects
        components.events.addEventListener('connection:open', () => {
            this.maybePruneConnections()
                .catch(err => {
                this.log.error(err);
            });
        });
    }
    /**
     * If we have more connections than our maximum, select some excess connections
     * to prune based on peer value
     */
    async maybePruneConnections() {
        const connections = this.connectionManager.getConnections();
        const numConnections = connections.length;
        const toPrune = Math.max(numConnections - this.maxConnections, 0);
        this.log('checking max connections limit %d/%d', numConnections, this.maxConnections);
        if (numConnections <= this.maxConnections) {
            return;
        }
        this.log('max connections limit exceeded %d/%d, pruning %d connection(s)', numConnections, this.maxConnections, toPrune);
        const peerValues = new PeerMap();
        // work out peer values
        for (const connection of connections) {
            const remotePeer = connection.remotePeer;
            if (peerValues.has(remotePeer)) {
                continue;
            }
            peerValues.set(remotePeer, 0);
            try {
                const peer = await this.peerStore.get(remotePeer);
                // sum all tag values
                peerValues.set(remotePeer, [...peer.tags.values()].reduce((acc, curr) => {
                    return acc + curr.value;
                }, 0));
            }
            catch (err) {
                if (err.code !== 'ERR_NOT_FOUND') {
                    this.log.error('error loading peer tags', err);
                }
            }
        }
        // sort by value, lowest to highest
        const sortedConnections = connections.sort((a, b) => {
            const peerAValue = peerValues.get(a.remotePeer) ?? 0;
            const peerBValue = peerValues.get(b.remotePeer) ?? 0;
            if (peerAValue > peerBValue) {
                return 1;
            }
            if (peerAValue < peerBValue) {
                return -1;
            }
            // if the peers have an equal tag value then we want to close short-lived connections first
            const connectionALifespan = a.timeline.open;
            const connectionBLifespan = b.timeline.open;
            if (connectionALifespan < connectionBLifespan) {
                return 1;
            }
            if (connectionALifespan > connectionBLifespan) {
                return -1;
            }
            return 0;
        });
        // close some connections
        const toClose = [];
        for (const connection of sortedConnections) {
            this.log('too many connections open - closing a connection to %p', connection.remotePeer);
            // check allow list
            const connectionInAllowList = this.allow.some((ma) => {
                return connection.remoteAddr.toString().startsWith(ma.toString());
            });
            // Connections in the allow list should be excluded from pruning
            if (!connectionInAllowList) {
                toClose.push(connection);
            }
            if (toClose.length === toPrune) {
                break;
            }
        }
        // close connections
        await Promise.all(toClose.map(async (connection) => {
            try {
                await connection.close();
            }
            catch (err) {
                this.log.error(err);
            }
        }));
        // despatch prune event
        this.events.safeDispatchEvent('connection:prune', { detail: toClose });
    }
}
//# sourceMappingURL=connection-pruner.js.map