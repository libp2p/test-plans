import { CodeError } from '@libp2p/interface/errors';
import merge from 'it-merge';
import { pipe } from 'it-pipe';
import { codes, messages } from '../errors.js';
import { storeAddresses, uniquePeers, requirePeers } from './utils.js';
export class CompoundContentRouting {
    routers;
    started;
    components;
    constructor(components, init) {
        this.routers = init.routers ?? [];
        this.started = false;
        this.components = components;
    }
    isStarted() {
        return this.started;
    }
    async start() {
        this.started = true;
    }
    async stop() {
        this.started = false;
    }
    /**
     * Iterates over all content routers in parallel to find providers of the given key
     */
    async *findProviders(key, options = {}) {
        if (this.routers.length === 0) {
            throw new CodeError('No content routers available', codes.ERR_NO_ROUTERS_AVAILABLE);
        }
        yield* pipe(merge(...this.routers.map(router => router.findProviders(key, options))), (source) => storeAddresses(source, this.components.peerStore), (source) => uniquePeers(source), (source) => requirePeers(source));
    }
    /**
     * Iterates over all content routers in parallel to notify it is
     * a provider of the given key
     */
    async provide(key, options = {}) {
        if (this.routers.length === 0) {
            throw new CodeError('No content routers available', codes.ERR_NO_ROUTERS_AVAILABLE);
        }
        await Promise.all(this.routers.map(async (router) => { await router.provide(key, options); }));
    }
    /**
     * Store the given key/value pair in the available content routings
     */
    async put(key, value, options) {
        if (!this.isStarted()) {
            throw new CodeError(messages.NOT_STARTED_YET, codes.DHT_NOT_STARTED);
        }
        await Promise.all(this.routers.map(async (router) => {
            await router.put(key, value, options);
        }));
    }
    /**
     * Get the value to the given key.
     * Times out after 1 minute by default.
     */
    async get(key, options) {
        if (!this.isStarted()) {
            throw new CodeError(messages.NOT_STARTED_YET, codes.DHT_NOT_STARTED);
        }
        return Promise.any(this.routers.map(async (router) => {
            return router.get(key, options);
        }));
    }
}
//# sourceMappingURL=index.js.map