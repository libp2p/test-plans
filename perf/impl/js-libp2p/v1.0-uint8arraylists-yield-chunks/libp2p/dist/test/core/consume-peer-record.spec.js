/* eslint-env mocha */
import { plaintext } from '@libp2p/plaintext';
import { webSockets } from '@libp2p/websockets';
import { multiaddr } from '@multiformats/multiaddr';
import { createLibp2pNode } from '../../src/libp2p.js';
import { createPeerId } from '../fixtures/creators/peer.js';
describe('Consume peer record', () => {
    let libp2p;
    beforeEach(async () => {
        const peerId = await createPeerId();
        libp2p = await createLibp2pNode({
            peerId,
            transports: [
                webSockets()
            ],
            connectionEncryption: [
                plaintext()
            ]
        });
    });
    afterEach(async () => {
        await libp2p.stop();
    });
    it('should update addresses when observed addrs are confirmed', async () => {
        let done;
        libp2p.peerStore.patch = async () => {
            done();
            return {};
        };
        const p = new Promise(resolve => {
            done = resolve;
        });
        await libp2p.start();
        libp2p.components.addressManager.confirmObservedAddr(multiaddr('/ip4/123.123.123.123/tcp/3983'));
        await p;
        await libp2p.stop();
    });
});
//# sourceMappingURL=consume-peer-record.spec.js.map