import { CodeError } from '@libp2p/interface/errors';
import filter from 'it-filter';
import map from 'it-map';
/**
 * Store the multiaddrs from every peer in the passed peer store
 */
export async function* storeAddresses(source, peerStore) {
    yield* map(source, async (peer) => {
        // ensure we have the addresses for a given peer
        await peerStore.merge(peer.id, {
            multiaddrs: peer.multiaddrs
        });
        return peer;
    });
}
/**
 * Filter peers by unique peer id
 */
export function uniquePeers(source) {
    /** @type Set<string> */
    const seen = new Set();
    return filter(source, (peer) => {
        // dedupe by peer id
        if (seen.has(peer.id.toString())) {
            return false;
        }
        seen.add(peer.id.toString());
        return true;
    });
}
/**
 * Require at least `min` peers to be yielded from `source`
 */
export async function* requirePeers(source, min = 1) {
    let seen = 0;
    for await (const peer of source) {
        seen++;
        yield peer;
    }
    if (seen < min) {
        throw new CodeError(`more peers required, seen: ${seen}  min: ${min}`, 'NOT_FOUND');
    }
}
//# sourceMappingURL=utils.js.map