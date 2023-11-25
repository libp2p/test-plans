/* eslint-env mocha */
import { plaintext } from '@libp2p/plaintext';
import { webSockets } from '@libp2p/websockets';
import { createLibp2p } from '../../src/index.js';
import { createPeerId } from '../fixtures/creators/peer.js';
describe('Connection encryption configuration', () => {
    let peerId;
    before(async () => {
        peerId = await createPeerId();
    });
    it('can be created', async () => {
        const config = {
            peerId,
            start: false,
            transports: [
                webSockets()
            ],
            connectionEncryption: [
                plaintext()
            ]
        };
        await createLibp2p(config);
    });
});
//# sourceMappingURL=encryption.spec.js.map