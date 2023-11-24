/* eslint-env mocha */
import { TypedEventEmitter } from '@libp2p/interface/events';
import { defaultLogger } from '@libp2p/logger';
import { createEd25519PeerId } from '@libp2p/peer-id-factory';
import { multiaddr } from '@multiformats/multiaddr';
import { expect } from 'aegir/chai';
import delay from 'delay';
import Sinon from 'sinon';
import { stubInterface } from 'sinon-ts';
import { DefaultAddressManager } from '../../src/address-manager/index.js';
const listenAddresses = ['/ip4/127.0.0.1/tcp/15006/ws', '/ip4/127.0.0.1/tcp/15008/ws'];
const announceAddreses = ['/dns4/peer.io'];
describe('Address Manager', () => {
    let peerId;
    let peerStore;
    let events;
    beforeEach(async () => {
        peerId = await createEd25519PeerId();
        peerStore = stubInterface({
            patch: Sinon.stub().resolves({})
        });
        events = new TypedEventEmitter();
    });
    it('should not need any addresses', () => {
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        }, {
            announceFilter: stubInterface()
        });
        expect(am.getListenAddrs()).to.be.empty();
        expect(am.getAnnounceAddrs()).to.be.empty();
    });
    it('should return listen multiaddrs on get', () => {
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        }, {
            announceFilter: stubInterface(),
            listen: listenAddresses
        });
        expect(am.getListenAddrs()).to.have.lengthOf(listenAddresses.length);
        expect(am.getAnnounceAddrs()).to.be.empty();
        const listenMultiaddrs = am.getListenAddrs();
        expect(listenMultiaddrs.length).to.equal(2);
        expect(listenMultiaddrs[0].equals(multiaddr(listenAddresses[0]))).to.equal(true);
        expect(listenMultiaddrs[1].equals(multiaddr(listenAddresses[1]))).to.equal(true);
    });
    it('should return announce multiaddrs on get', () => {
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        }, {
            announceFilter: stubInterface(),
            listen: listenAddresses,
            announce: announceAddreses
        });
        expect(am.getListenAddrs()).to.have.lengthOf(listenAddresses.length);
        expect(am.getAnnounceAddrs()).to.have.lengthOf(announceAddreses.length);
        const announceMultiaddrs = am.getAnnounceAddrs();
        expect(announceMultiaddrs.length).to.equal(1);
        expect(announceMultiaddrs[0].equals(multiaddr(announceAddreses[0]))).to.equal(true);
    });
    it('should add observed addresses', () => {
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        }, {
            announceFilter: stubInterface()
        });
        expect(am.getObservedAddrs()).to.be.empty();
        am.addObservedAddr(multiaddr('/ip4/123.123.123.123/tcp/39201'));
        expect(am.getObservedAddrs()).to.have.lengthOf(1);
    });
    it('should allow duplicate listen addresses', () => {
        const ma = multiaddr('/ip4/0.0.0.0/tcp/0');
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        }, {
            announceFilter: stubInterface(),
            listen: [
                ma.toString(),
                ma.toString()
            ]
        });
        expect(am.getListenAddrs()).to.deep.equal([
            ma,
            ma
        ]);
    });
    it('should dedupe added observed addresses', () => {
        const ma = multiaddr('/ip4/123.123.123.123/tcp/39201');
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        }, {
            announceFilter: stubInterface()
        });
        expect(am.getObservedAddrs()).to.be.empty();
        am.addObservedAddr(ma);
        am.addObservedAddr(ma);
        am.addObservedAddr(ma);
        expect(am.getObservedAddrs()).to.have.lengthOf(1);
        expect(am.getObservedAddrs().map(ma => ma.toString())).to.include(ma.toString());
    });
    it('should only set addresses once', async () => {
        const ma = '/ip4/123.123.123.123/tcp/39201';
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface({
                getAddrs: Sinon.stub().returns([])
            }),
            peerStore,
            events,
            logger: defaultLogger()
        });
        am.confirmObservedAddr(multiaddr(ma));
        am.confirmObservedAddr(multiaddr(ma));
        am.confirmObservedAddr(multiaddr(ma));
        am.confirmObservedAddr(multiaddr(`${ma.toString()}/p2p/${peerId.toString()}`));
        // wait for address manager _updatePeerStoreAddresses debounce
        await delay(1500);
        expect(peerStore.patch).to.have.property('callCount', 1);
    });
    it('should strip our peer address from added observed addresses', () => {
        const ma = multiaddr('/ip4/123.123.123.123/tcp/39201');
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        });
        expect(am.getObservedAddrs()).to.be.empty();
        am.addObservedAddr(ma);
        am.addObservedAddr(multiaddr(`${ma.toString()}/p2p/${peerId.toString()}`));
        expect(am.getObservedAddrs()).to.have.lengthOf(1);
        expect(am.getObservedAddrs().map(ma => ma.toString())).to.include(ma.toString());
    });
    it('should strip our peer address from added observed addresses in difference formats', () => {
        const ma = multiaddr('/ip4/123.123.123.123/tcp/39201');
        const am = new DefaultAddressManager({
            peerId,
            transportManager: stubInterface(),
            peerStore,
            events,
            logger: defaultLogger()
        });
        expect(am.getObservedAddrs()).to.be.empty();
        am.addObservedAddr(ma);
        am.addObservedAddr(multiaddr(`${ma.toString()}/p2p/${peerId.toString()}`));
        expect(am.getObservedAddrs()).to.have.lengthOf(1);
        expect(am.getObservedAddrs().map(ma => ma.toString())).to.include(ma.toString());
    });
    it('should not add our peer id to path multiaddrs', () => {
        const ma = '/unix/foo/bar/baz';
        const transportManager = stubInterface();
        const am = new DefaultAddressManager({
            peerId,
            transportManager,
            peerStore,
            events,
            logger: defaultLogger()
        }, {
            listen: [ma],
            announce: []
        });
        transportManager.getAddrs.returns([multiaddr(ma)]);
        const addrs = am.getAddresses();
        expect(addrs).to.have.lengthOf(1);
        expect(addrs[0].toString()).to.not.include(`/p2p/${peerId.toString()}`);
    });
});
//# sourceMappingURL=address-manager.spec.js.map