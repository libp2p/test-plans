/* eslint-env mocha */
import { yamux } from '@chainsafe/libp2p-yamux';
import { kadDHT } from '@libp2p/kad-dht';
import { mplex } from '@libp2p/mplex';
import { plaintext } from '@libp2p/plaintext';
import { tcp } from '@libp2p/tcp';
import { multiaddr } from '@multiformats/multiaddr';
import { expect } from 'aegir/chai';
import pWaitFor from 'p-wait-for';
import { fromString as uint8ArrayFromString } from 'uint8arrays/from-string';
import { createLibp2p } from '../../../src/index.js';
import { createPeerId } from '../../fixtures/creators/peer.js';
import { subsystemMulticodecs } from './utils.js';
const listenAddr = multiaddr('/ip4/127.0.0.1/tcp/8000');
const remoteListenAddr = multiaddr('/ip4/127.0.0.1/tcp/8001');
async function getRemoteAddr(remotePeerId, libp2p) {
    const { addresses } = await libp2p.peerStore.get(remotePeerId);
    if (addresses.length === 0) {
        throw new Error('No addrs found');
    }
    const addr = addresses[0];
    return addr.multiaddr.encapsulate(`/p2p/${remotePeerId.toString()}`);
}
describe('DHT subsystem operates correctly', () => {
    let peerId;
    let remotePeerId;
    let libp2p;
    let remoteLibp2p;
    let remAddr;
    beforeEach(async () => {
        [peerId, remotePeerId] = await Promise.all([
            createPeerId(),
            createPeerId()
        ]);
    });
    describe('dht started before connect', () => {
        beforeEach(async () => {
            libp2p = await createLibp2p({
                peerId,
                addresses: {
                    listen: [listenAddr.toString()]
                },
                transports: [
                    tcp()
                ],
                connectionEncryption: [
                    plaintext()
                ],
                streamMuxers: [
                    yamux(),
                    mplex()
                ],
                services: {
                    dht: kadDHT({
                        allowQueryWithZeroPeers: true
                    })
                }
            });
            remoteLibp2p = await createLibp2p({
                peerId: remotePeerId,
                addresses: {
                    listen: [remoteListenAddr.toString()]
                },
                transports: [
                    tcp()
                ],
                connectionEncryption: [
                    plaintext()
                ],
                streamMuxers: [
                    yamux(),
                    mplex()
                ],
                services: {
                    dht: kadDHT({
                        allowQueryWithZeroPeers: true
                    })
                }
            });
            await Promise.all([
                libp2p.start(),
                remoteLibp2p.start()
            ]);
            await libp2p.peerStore.patch(remotePeerId, {
                multiaddrs: [remoteListenAddr]
            });
            remAddr = await getRemoteAddr(remotePeerId, libp2p);
        });
        afterEach(async () => {
            if (libp2p != null) {
                await libp2p.stop();
            }
            if (remoteLibp2p != null) {
                await remoteLibp2p.stop();
            }
        });
        it('should get notified of connected peers on dial', async () => {
            const stream = await libp2p.dialProtocol(remAddr, subsystemMulticodecs);
            expect(stream).to.exist();
            return Promise.all([
                pWaitFor(() => libp2p.services.dht.lan.routingTable.size === 1),
                pWaitFor(() => remoteLibp2p.services.dht.lan.routingTable.size === 1)
            ]);
        });
        it('should put on a peer and get from the other', async () => {
            const key = uint8ArrayFromString('hello');
            const value = uint8ArrayFromString('world');
            await libp2p.dialProtocol(remotePeerId, subsystemMulticodecs);
            await Promise.all([
                pWaitFor(() => libp2p.services.dht.lan.routingTable.size === 1),
                pWaitFor(() => remoteLibp2p.services.dht.lan.routingTable.size === 1)
            ]);
            await libp2p.contentRouting.put(key, value);
            const fetchedValue = await remoteLibp2p.contentRouting.get(key);
            expect(fetchedValue).to.equalBytes(value);
        });
    });
});
//# sourceMappingURL=operation.node.js.map