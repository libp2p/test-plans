/* eslint-env mocha */
import { plaintext } from '@libp2p/plaintext';
import { tcp } from '@libp2p/tcp';
import { expect } from 'aegir/chai';
import { createLibp2pNode } from '../../src/libp2p.js';
import { createPeerId } from '../fixtures/creators/peer.js';
const listenAddr = '/ip4/0.0.0.0/tcp/0';
describe('Listening', () => {
    let peerId;
    let libp2p;
    before(async () => {
        peerId = await createPeerId();
    });
    after(async () => {
        await libp2p.stop();
    });
    it('should replace wildcard host and port with actual host and port on startup', async () => {
        libp2p = await createLibp2pNode({
            peerId,
            addresses: {
                listen: [listenAddr]
            },
            transports: [
                tcp()
            ],
            connectionEncryption: [
                plaintext()
            ]
        });
        await libp2p.start();
        const addrs = libp2p.components.transportManager.getAddrs();
        // Should get something like:
        //   /ip4/127.0.0.1/tcp/50866
        //   /ip4/192.168.1.2/tcp/50866
        expect(addrs.length).to.be.at.least(1);
        for (const addr of addrs) {
            const opts = addr.toOptions();
            expect(opts.family).to.equal(4);
            expect(opts.transport).to.equal('tcp');
            expect(opts.host).to.match(/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/);
            expect(opts.port).to.be.gt(0);
        }
    });
});
//# sourceMappingURL=listening.node.js.map