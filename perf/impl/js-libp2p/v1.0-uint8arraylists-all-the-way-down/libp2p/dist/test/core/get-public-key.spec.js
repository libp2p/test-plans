/* eslint-env mocha */
import { kadDHT } from '@libp2p/kad-dht';
import { plaintext } from '@libp2p/plaintext';
import { webSockets } from '@libp2p/websockets';
import { expect } from 'aegir/chai';
import sinon from 'sinon';
import { createLibp2pNode } from '../../src/libp2p.js';
import { createPeerId } from '../fixtures/creators/peer.js';
describe('getPublicKey', () => {
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
            ],
            services: {
                dht: kadDHT()
            }
        });
        await libp2p.start();
    });
    afterEach(async () => {
        await libp2p.stop();
    });
    it('should extract embedded public key', async () => {
        const otherPeer = await createPeerId();
        const key = await libp2p.getPublicKey(otherPeer);
        expect(otherPeer.publicKey).to.equalBytes(key);
    });
    it('should get key from the keystore', async () => {
        const otherPeer = await createPeerId({ opts: { type: 'rsa' } });
        if (otherPeer.publicKey == null) {
            throw new Error('Public key was missing');
        }
        await libp2p.peerStore.patch(otherPeer, {
            publicKey: otherPeer.publicKey
        });
        const key = await libp2p.getPublicKey(otherPeer);
        expect(otherPeer.publicKey).to.equalBytes(key);
    });
    it('should query the DHT when the key is not in the keystore', async () => {
        const otherPeer = await createPeerId({ opts: { type: 'rsa' } });
        if (otherPeer.publicKey == null) {
            throw new Error('Public key was missing');
        }
        if (libp2p.services.dht == null) {
            throw new Error('DHT was not configured');
        }
        libp2p.services.dht.get = sinon.stub().returns([{
                name: 'VALUE',
                value: otherPeer.publicKey
            }]);
        const key = await libp2p.getPublicKey(otherPeer);
        expect(otherPeer.publicKey).to.equalBytes(key);
    });
});
//# sourceMappingURL=get-public-key.spec.js.map