/* eslint-env mocha */
import { plaintext } from '@libp2p/plaintext';
import { webSockets } from '@libp2p/websockets';
import { expect } from 'aegir/chai';
import { pEvent } from 'p-event';
import { createLibp2p } from '../../src/index.js';
describe('events', () => {
    let node;
    afterEach(async () => {
        if (node != null) {
            await node.stop();
        }
    });
    it('should emit a start event', async () => {
        node = await createLibp2p({
            start: false,
            transports: [
                webSockets()
            ],
            connectionEncryption: [
                plaintext()
            ]
        });
        const eventPromise = pEvent(node, 'start');
        await node.start();
        await expect(eventPromise).to.eventually.have.property('detail', node);
    });
    it('should emit a stop event', async () => {
        node = await createLibp2p({
            transports: [
                webSockets()
            ],
            connectionEncryption: [
                plaintext()
            ]
        });
        const eventPromise = pEvent(node, 'stop');
        await node.stop();
        await expect(eventPromise).to.eventually.have.property('detail', node);
    });
});
//# sourceMappingURL=events.spec.js.map