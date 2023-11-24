/* eslint-env mocha */
import { expect } from 'aegir/chai';
import sinon from 'sinon';
import { stubInterface } from 'sinon-ts';
import { createLibp2pNode } from '../../src/libp2p.js';
import { createBaseOptions } from '../fixtures/base-options.browser.js';
import { createPeerId } from '../fixtures/creators/peer.js';
describe('peer discovery', () => {
    describe('basic functions', () => {
        let peerId;
        let libp2p;
        before(async () => {
            peerId = await createPeerId();
        });
        afterEach(async () => {
            if (libp2p != null) {
                await libp2p.stop();
            }
            sinon.reset();
        });
        it('should start/stop startable discovery on libp2p start/stop', async () => {
            const discovery = stubInterface();
            libp2p = await createLibp2pNode(createBaseOptions({
                peerId,
                peerDiscovery: [
                    () => discovery
                ]
            }));
            await libp2p.start();
            expect(discovery.start.calledOnce).to.be.true();
            expect(discovery.stop.called).to.be.false();
            await libp2p.stop();
            expect(discovery.start.calledOnce).to.be.true();
            expect(discovery.stop.calledOnce).to.be.true();
        });
    });
});
//# sourceMappingURL=index.spec.js.map