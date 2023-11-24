import { CodeError } from '@libp2p/interface/errors';
import filter from 'it-filter';
import first from 'it-first';
import merge from 'it-merge';
import { pipe } from 'it-pipe';
import { storeAddresses, uniquePeers, requirePeers } from './content-routing/utils.js';
import { codes, messages } from './errors.js';
export class DefaultPeerRouting {
    log;
    peerId;
    peerStore;
    routers;
    constructor(components, init) {
        this.log = components.logger.forComponent('libp2p:peer-routing');
        this.peerId = components.peerId;
        this.peerStore = components.peerStore;
        this.routers = init.routers ?? [];
    }
    /**
     * Iterates over all peer routers in parallel to find the given peer
     */
    async findPeer(id, options) {
        if (this.routers.length === 0) {
            throw new CodeError('No peer routers available', codes.ERR_NO_ROUTERS_AVAILABLE);
        }
        if (id.toString() === this.peerId.toString()) {
            throw new CodeError('Should not try to find self', codes.ERR_FIND_SELF);
        }
        const self = this;
        const output = await pipe(merge(...this.routers.map(router => (async function* () {
            try {
                yield await router.findPeer(id, options);
            }
            catch (err) {
                self.log.error(err);
            }
        })())), (source) => filter(source, Boolean), (source) => storeAddresses(source, this.peerStore), async (source) => first(source));
        if (output != null) {
            return output;
        }
        throw new CodeError(messages.NOT_FOUND, codes.ERR_NOT_FOUND);
    }
    /**
     * Attempt to find the closest peers on the network to the given key
     */
    async *getClosestPeers(key, options) {
        if (this.routers.length === 0) {
            throw new CodeError('No peer routers available', codes.ERR_NO_ROUTERS_AVAILABLE);
        }
        yield* pipe(merge(...this.routers.map(router => router.getClosestPeers(key, options))), (source) => storeAddresses(source, this.peerStore), (source) => uniquePeers(source), (source) => requirePeers(source));
    }
}
//# sourceMappingURL=peer-routing.js.map