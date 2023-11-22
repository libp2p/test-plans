import { unmarshalPublicKey } from '@libp2p/crypto/keys';
import { contentRouting } from '@libp2p/interface/content-routing';
import { CodeError } from '@libp2p/interface/errors';
import { TypedEventEmitter, CustomEvent, setMaxListeners } from '@libp2p/interface/events';
import { peerDiscovery } from '@libp2p/interface/peer-discovery';
import { peerRouting } from '@libp2p/interface/peer-routing';
import { peerLogger } from '@libp2p/logger';
import { PeerSet } from '@libp2p/peer-collections';
import { peerIdFromString } from '@libp2p/peer-id';
import { createEd25519PeerId } from '@libp2p/peer-id-factory';
import { PersistentPeerStore } from '@libp2p/peer-store';
import { isMultiaddr } from '@multiformats/multiaddr';
import { MemoryDatastore } from 'datastore-core/memory';
import { concat as uint8ArrayConcat } from 'uint8arrays/concat';
import { fromString as uint8ArrayFromString } from 'uint8arrays/from-string';
import { DefaultAddressManager } from './address-manager/index.js';
import { defaultComponents } from './components.js';
import { connectionGater } from './config/connection-gater.js';
import { validateConfig } from './config.js';
import { DefaultConnectionManager } from './connection-manager/index.js';
import { CompoundContentRouting } from './content-routing/index.js';
import { codes } from './errors.js';
import { DefaultPeerRouting } from './peer-routing.js';
import { DefaultRegistrar } from './registrar.js';
import { DefaultTransportManager } from './transport-manager.js';
import { DefaultUpgrader } from './upgrader.js';
import * as pkg from './version.js';
export class Libp2pNode extends TypedEventEmitter {
    peerId;
    peerStore;
    contentRouting;
    peerRouting;
    metrics;
    services;
    logger;
    components;
    #started;
    log;
    constructor(init) {
        super();
        // event bus - components can listen to this emitter to be notified of system events
        // and also cause them to be emitted
        const events = new TypedEventEmitter();
        const originalDispatch = events.dispatchEvent.bind(events);
        events.dispatchEvent = (evt) => {
            const internalResult = originalDispatch(evt);
            const externalResult = this.dispatchEvent(new CustomEvent(evt.type, { detail: evt.detail }));
            return internalResult || externalResult;
        };
        // This emitter gets listened to a lot
        setMaxListeners(Infinity, events);
        this.#started = false;
        this.peerId = init.peerId;
        this.logger = init.logger ?? peerLogger(this.peerId);
        this.log = this.logger.forComponent('libp2p');
        // @ts-expect-error {} may not be of type T
        this.services = {};
        const components = this.components = defaultComponents({
            peerId: init.peerId,
            nodeInfo: init.nodeInfo ?? {
                name: pkg.name,
                version: pkg.version
            },
            logger: this.logger,
            events,
            datastore: init.datastore ?? new MemoryDatastore(),
            connectionGater: connectionGater(init.connectionGater)
        });
        this.peerStore = this.configureComponent('peerStore', new PersistentPeerStore(components, {
            addressFilter: this.components.connectionGater.filterMultiaddrForPeer,
            ...init.peerStore
        }));
        // Create Metrics
        if (init.metrics != null) {
            this.metrics = this.configureComponent('metrics', init.metrics(this.components));
        }
        components.events.addEventListener('peer:update', evt => {
            // if there was no peer previously in the peer store this is a new peer
            if (evt.detail.previous == null) {
                const peerInfo = {
                    id: evt.detail.peer.id,
                    multiaddrs: evt.detail.peer.addresses.map(a => a.multiaddr)
                };
                components.events.safeDispatchEvent('peer:discovery', { detail: peerInfo });
            }
        });
        // Set up connection protector if configured
        if (init.connectionProtector != null) {
            this.configureComponent('connectionProtector', init.connectionProtector(components));
        }
        // Set up the Upgrader
        this.components.upgrader = new DefaultUpgrader(this.components, {
            connectionEncryption: (init.connectionEncryption ?? []).map((fn, index) => this.configureComponent(`connection-encryption-${index}`, fn(this.components))),
            muxers: (init.streamMuxers ?? []).map((fn, index) => this.configureComponent(`stream-muxers-${index}`, fn(this.components))),
            inboundUpgradeTimeout: init.connectionManager.inboundUpgradeTimeout
        });
        // Setup the transport manager
        this.configureComponent('transportManager', new DefaultTransportManager(this.components, init.transportManager));
        // Create the Connection Manager
        this.configureComponent('connectionManager', new DefaultConnectionManager(this.components, init.connectionManager));
        // Create the Registrar
        this.configureComponent('registrar', new DefaultRegistrar(this.components));
        // Addresses {listen, announce, noAnnounce}
        this.configureComponent('addressManager', new DefaultAddressManager(this.components, init.addresses));
        // Peer routers
        const peerRouters = (init.peerRouters ?? []).map((fn, index) => this.configureComponent(`peer-router-${index}`, fn(this.components)));
        this.peerRouting = this.components.peerRouting = this.configureComponent('peerRouting', new DefaultPeerRouting(this.components, {
            routers: peerRouters
        }));
        // Content routers
        const contentRouters = (init.contentRouters ?? []).map((fn, index) => this.configureComponent(`content-router-${index}`, fn(this.components)));
        this.contentRouting = this.components.contentRouting = this.configureComponent('contentRouting', new CompoundContentRouting(this.components, {
            routers: contentRouters
        }));
        (init.peerDiscovery ?? []).forEach((fn, index) => {
            const service = this.configureComponent(`peer-discovery-${index}`, fn(this.components));
            service.addEventListener('peer', (evt) => {
                this.#onDiscoveryPeer(evt);
            });
        });
        // Transport modules
        init.transports.forEach((fn, index) => {
            this.components.transportManager.add(this.configureComponent(`transport-${index}`, fn(this.components)));
        });
        // User defined modules
        if (init.services != null) {
            for (const name of Object.keys(init.services)) {
                const createService = init.services[name];
                const service = createService(this.components);
                if (service == null) {
                    this.log.error('service factory %s returned null or undefined instance', name);
                    continue;
                }
                this.services[name] = service;
                this.configureComponent(name, service);
                if (service[contentRouting] != null) {
                    this.log('registering service %s for content routing', name);
                    contentRouters.push(service[contentRouting]);
                }
                if (service[peerRouting] != null) {
                    this.log('registering service %s for peer routing', name);
                    peerRouters.push(service[peerRouting]);
                }
                if (service[peerDiscovery] != null) {
                    this.log('registering service %s for peer discovery', name);
                    service[peerDiscovery].addEventListener('peer', (evt) => {
                        this.#onDiscoveryPeer(evt);
                    });
                }
            }
        }
    }
    configureComponent(name, component) {
        if (component == null) {
            this.log.error('component %s was null or undefined', name);
        }
        this.components[name] = component;
        return component;
    }
    /**
     * Starts the libp2p node and all its subsystems
     */
    async start() {
        if (this.#started) {
            return;
        }
        this.#started = true;
        this.log('libp2p is starting');
        try {
            await this.components.beforeStart?.();
            await this.components.start();
            await this.components.afterStart?.();
            this.safeDispatchEvent('start', { detail: this });
            this.log('libp2p has started');
        }
        catch (err) {
            this.log.error('An error occurred starting libp2p', err);
            await this.stop();
            throw err;
        }
    }
    /**
     * Stop the libp2p node by closing its listeners and open connections
     */
    async stop() {
        if (!this.#started) {
            return;
        }
        this.log('libp2p is stopping');
        this.#started = false;
        await this.components.beforeStop?.();
        await this.components.stop();
        await this.components.afterStop?.();
        this.safeDispatchEvent('stop', { detail: this });
        this.log('libp2p has stopped');
    }
    isStarted() {
        return this.#started;
    }
    getConnections(peerId) {
        return this.components.connectionManager.getConnections(peerId);
    }
    getDialQueue() {
        return this.components.connectionManager.getDialQueue();
    }
    getPeers() {
        const peerSet = new PeerSet();
        for (const conn of this.components.connectionManager.getConnections()) {
            peerSet.add(conn.remotePeer);
        }
        return Array.from(peerSet);
    }
    async dial(peer, options = {}) {
        return this.components.connectionManager.openConnection(peer, options);
    }
    async dialProtocol(peer, protocols, options = {}) {
        if (protocols == null) {
            throw new CodeError('no protocols were provided to open a stream', codes.ERR_INVALID_PROTOCOLS_FOR_STREAM);
        }
        protocols = Array.isArray(protocols) ? protocols : [protocols];
        if (protocols.length === 0) {
            throw new CodeError('no protocols were provided to open a stream', codes.ERR_INVALID_PROTOCOLS_FOR_STREAM);
        }
        const connection = await this.dial(peer, options);
        return connection.newStream(protocols, options);
    }
    getMultiaddrs() {
        return this.components.addressManager.getAddresses();
    }
    getProtocols() {
        return this.components.registrar.getProtocols();
    }
    async hangUp(peer, options = {}) {
        if (isMultiaddr(peer)) {
            peer = peerIdFromString(peer.getPeerId() ?? '');
        }
        await this.components.connectionManager.closeConnections(peer, options);
    }
    /**
     * Get the public key for the given peer id
     */
    async getPublicKey(peer, options = {}) {
        this.log('getPublicKey %p', peer);
        if (peer.publicKey != null) {
            return peer.publicKey;
        }
        const peerInfo = await this.peerStore.get(peer);
        if (peerInfo.id.publicKey != null) {
            return peerInfo.id.publicKey;
        }
        const peerKey = uint8ArrayConcat([
            uint8ArrayFromString('/pk/'),
            peer.multihash.digest
        ]);
        // search any available content routing methods
        const bytes = await this.contentRouting.get(peerKey, options);
        // ensure the returned key is valid
        unmarshalPublicKey(bytes);
        await this.peerStore.patch(peer, {
            publicKey: bytes
        });
        return bytes;
    }
    async handle(protocols, handler, options) {
        if (!Array.isArray(protocols)) {
            protocols = [protocols];
        }
        await Promise.all(protocols.map(async (protocol) => {
            await this.components.registrar.handle(protocol, handler, options);
        }));
    }
    async unhandle(protocols) {
        if (!Array.isArray(protocols)) {
            protocols = [protocols];
        }
        await Promise.all(protocols.map(async (protocol) => {
            await this.components.registrar.unhandle(protocol);
        }));
    }
    async register(protocol, topology) {
        return this.components.registrar.register(protocol, topology);
    }
    unregister(id) {
        this.components.registrar.unregister(id);
    }
    /**
     * Called whenever peer discovery services emit `peer` events and adds peers
     * to the peer store.
     */
    #onDiscoveryPeer(evt) {
        const { detail: peer } = evt;
        if (peer.id.toString() === this.peerId.toString()) {
            this.log.error(new Error(codes.ERR_DISCOVERED_SELF));
            return;
        }
        void this.components.peerStore.merge(peer.id, {
            multiaddrs: peer.multiaddrs
        })
            .catch(err => { this.log.error(err); });
    }
}
/**
 * Returns a new Libp2pNode instance - this exposes more of the internals than the
 * libp2p interface and is useful for testing and debugging.
 */
export async function createLibp2pNode(options) {
    options.peerId ??= await createEd25519PeerId();
    return new Libp2pNode(validateConfig(options));
}
//# sourceMappingURL=libp2p.js.map