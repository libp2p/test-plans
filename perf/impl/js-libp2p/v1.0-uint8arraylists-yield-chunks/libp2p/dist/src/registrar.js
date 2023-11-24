import { CodeError } from '@libp2p/interface/errors';
import merge from 'merge-options';
import { codes } from './errors.js';
export const DEFAULT_MAX_INBOUND_STREAMS = 32;
export const DEFAULT_MAX_OUTBOUND_STREAMS = 64;
/**
 * Responsible for notifying registered protocols of events in the network.
 */
export class DefaultRegistrar {
    log;
    topologies;
    handlers;
    components;
    constructor(components) {
        this.log = components.logger.forComponent('libp2p:registrar');
        this.topologies = new Map();
        this.handlers = new Map();
        this.components = components;
        this._onDisconnect = this._onDisconnect.bind(this);
        this._onPeerUpdate = this._onPeerUpdate.bind(this);
        this._onPeerIdentify = this._onPeerIdentify.bind(this);
        this.components.events.addEventListener('peer:disconnect', this._onDisconnect);
        this.components.events.addEventListener('peer:update', this._onPeerUpdate);
        this.components.events.addEventListener('peer:identify', this._onPeerIdentify);
    }
    getProtocols() {
        return Array.from(new Set([
            ...this.handlers.keys()
        ])).sort();
    }
    getHandler(protocol) {
        const handler = this.handlers.get(protocol);
        if (handler == null) {
            throw new CodeError(`No handler registered for protocol ${protocol}`, codes.ERR_NO_HANDLER_FOR_PROTOCOL);
        }
        return handler;
    }
    getTopologies(protocol) {
        const topologies = this.topologies.get(protocol);
        if (topologies == null) {
            return [];
        }
        return [
            ...topologies.values()
        ];
    }
    /**
     * Registers the `handler` for each protocol
     */
    async handle(protocol, handler, opts) {
        if (this.handlers.has(protocol)) {
            throw new CodeError(`Handler already registered for protocol ${protocol}`, codes.ERR_PROTOCOL_HANDLER_ALREADY_REGISTERED);
        }
        const options = merge.bind({ ignoreUndefined: true })({
            maxInboundStreams: DEFAULT_MAX_INBOUND_STREAMS,
            maxOutboundStreams: DEFAULT_MAX_OUTBOUND_STREAMS
        }, opts);
        this.handlers.set(protocol, {
            handler,
            options
        });
        // Add new protocol to self protocols in the peer store
        await this.components.peerStore.merge(this.components.peerId, {
            protocols: [protocol]
        });
    }
    /**
     * Removes the handler for each protocol. The protocol
     * will no longer be supported on streams.
     */
    async unhandle(protocols) {
        const protocolList = Array.isArray(protocols) ? protocols : [protocols];
        protocolList.forEach(protocol => {
            this.handlers.delete(protocol);
        });
        // Update self protocols in the peer store
        await this.components.peerStore.patch(this.components.peerId, {
            protocols: this.getProtocols()
        });
    }
    /**
     * Register handlers for a set of multicodecs given
     */
    async register(protocol, topology) {
        if (topology == null) {
            throw new CodeError('invalid topology', codes.ERR_INVALID_PARAMETERS);
        }
        // Create topology
        const id = `${(Math.random() * 1e9).toString(36)}${Date.now()}`;
        let topologies = this.topologies.get(protocol);
        if (topologies == null) {
            topologies = new Map();
            this.topologies.set(protocol, topologies);
        }
        topologies.set(id, topology);
        return id;
    }
    /**
     * Unregister topology
     */
    unregister(id) {
        for (const [protocol, topologies] of this.topologies.entries()) {
            if (topologies.has(id)) {
                topologies.delete(id);
                if (topologies.size === 0) {
                    this.topologies.delete(protocol);
                }
            }
        }
    }
    /**
     * Remove a disconnected peer from the record
     */
    _onDisconnect(evt) {
        const remotePeer = evt.detail;
        void this.components.peerStore.get(remotePeer)
            .then(peer => {
            for (const protocol of peer.protocols) {
                const topologies = this.topologies.get(protocol);
                if (topologies == null) {
                    // no topologies are interested in this protocol
                    continue;
                }
                for (const topology of topologies.values()) {
                    topology.onDisconnect?.(remotePeer);
                }
            }
        })
            .catch(err => {
            if (err.code === codes.ERR_NOT_FOUND) {
                // peer has not completed identify so they are not in the peer store
                return;
            }
            this.log.error('could not inform topologies of disconnecting peer %p', remotePeer, err);
        });
    }
    /**
     * When a peer is updated, if they have removed supported protocols notify any
     * topologies interested in the removed protocols.
     */
    _onPeerUpdate(evt) {
        const { peer, previous } = evt.detail;
        const removed = (previous?.protocols ?? []).filter(protocol => !peer.protocols.includes(protocol));
        for (const protocol of removed) {
            const topologies = this.topologies.get(protocol);
            if (topologies == null) {
                // no topologies are interested in this protocol
                continue;
            }
            for (const topology of topologies.values()) {
                topology.onDisconnect?.(peer.id);
            }
        }
    }
    /**
     * After identify has completed and we have received the list of supported
     * protocols, notify any topologies interested in those protocols.
     */
    _onPeerIdentify(evt) {
        const protocols = evt.detail.protocols;
        const connection = evt.detail.connection;
        const peerId = evt.detail.peerId;
        for (const protocol of protocols) {
            const topologies = this.topologies.get(protocol);
            if (topologies == null) {
                // no topologies are interested in this protocol
                continue;
            }
            for (const topology of topologies.values()) {
                if (connection.transient && topology.notifyOnTransient !== true) {
                    continue;
                }
                topology.onConnect?.(peerId, connection);
            }
        }
    }
}
//# sourceMappingURL=registrar.js.map