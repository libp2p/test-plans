import { createEd25519PeerId, createRSAPeerId } from '@libp2p/peer-id-factory';
import { multiaddr } from '@multiformats/multiaddr';
import pTimes from 'p-times';
import { createLibp2pNode } from '../../../src/libp2p.js';
import { createBaseOptions } from '../base-options.browser.js';
const listenAddr = multiaddr('/ip4/127.0.0.1/tcp/0');
/**
 * Create libp2p nodes.
 */
export async function createNode(options = {}) {
    const started = options.started ?? true;
    const config = options.config ?? {};
    const peerId = await createPeerId();
    const addresses = started
        ? {
            listen: [listenAddr.toString()],
            announce: [],
            noAnnounce: [],
            announceFilter: (addrs) => addrs
        }
        : {
            listen: [],
            announce: [],
            noAnnounce: [],
            announceFilter: (addrs) => addrs
        };
    const peer = await createLibp2pNode(createBaseOptions({
        peerId,
        addresses,
        start: started,
        ...config
    }));
    if (started) {
        await peer.start();
    }
    return peer;
}
export async function populateAddressBooks(peers) {
    for (let i = 0; i < peers.length; i++) {
        for (let j = 0; j < peers.length; j++) {
            if (i !== j) {
                await peers[i].peerStore.patch(peers[j].peerId, {
                    multiaddrs: peers[j].getMultiaddrs()
                });
            }
        }
    }
}
/**
 * Create Peer-id
 */
export async function createPeerId(options = {}) {
    const opts = options.opts ?? {};
    return opts.type === 'rsa' ? createRSAPeerId({ bits: opts.bits ?? 512 }) : createEd25519PeerId();
}
/**
 * Create Peer-ids
 */
export async function createPeerIds(count, options = {}) {
    const opts = options.opts ?? {};
    return pTimes(count, async (i) => createPeerId({ opts }));
}
//# sourceMappingURL=peer.js.map