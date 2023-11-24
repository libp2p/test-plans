/* eslint-env mocha */
import { yamux } from '@chainsafe/libp2p-yamux';
import { RELAY_V2_HOP_CODEC } from '@libp2p/circuit-relay-v2';
import { circuitRelayServer, circuitRelayTransport } from '@libp2p/circuit-relay-v2';
import { mockConnection, mockConnectionGater, mockDuplex, mockMultiaddrConnection } from '@libp2p/interface-compliance-tests/mocks';
import { mplex } from '@libp2p/mplex';
import { peerIdFromString } from '@libp2p/peer-id';
import { createEd25519PeerId } from '@libp2p/peer-id-factory';
import { plaintext } from '@libp2p/plaintext';
import { webSockets } from '@libp2p/websockets';
import * as filters from '@libp2p/websockets/filters';
import { multiaddr } from '@multiformats/multiaddr';
import { expect } from 'aegir/chai';
import pDefer from 'p-defer';
import sinon from 'sinon';
import { codes as ErrorCodes } from '../../src/errors.js';
import { createLibp2pNode } from '../../src/libp2p.js';
const relayAddr = multiaddr(process.env.RELAY_MULTIADDR);
const getDnsaddrStub = (peerId) => [
    `/dnsaddr/ams-1.bootstrap.libp2p.io/p2p/${peerId.toString()}`,
    `/dnsaddr/ams-2.bootstrap.libp2p.io/p2p/${peerId.toString()}`,
    `/dnsaddr/lon-1.bootstrap.libp2p.io/p2p/${peerId.toString()}`,
    `/dnsaddr/nrt-1.bootstrap.libp2p.io/p2p/${peerId.toString()}`,
    `/dnsaddr/nyc-1.bootstrap.libp2p.io/p2p/${peerId.toString()}`,
    `/dnsaddr/sfo-2.bootstrap.libp2p.io/p2p/${peerId.toString()}`
];
const relayedAddr = (peerId) => `${relayAddr.toString()}/p2p-circuit/p2p/${peerId.toString()}`;
const getDnsRelayedAddrStub = (peerId) => [
    `${relayedAddr(peerId)}`
];
describe('dialing (resolvable addresses)', () => {
    let libp2p;
    let remoteLibp2p;
    let resolver;
    beforeEach(async () => {
        resolver = sinon.stub();
        [libp2p, remoteLibp2p] = await Promise.all([
            createLibp2pNode({
                addresses: {
                    listen: [`${relayAddr.toString()}/p2p-circuit`]
                },
                transports: [
                    circuitRelayTransport(),
                    webSockets({
                        filter: filters.all
                    })
                ],
                streamMuxers: [
                    yamux(),
                    mplex()
                ],
                connectionManager: {
                    resolvers: {
                        dnsaddr: resolver
                    }
                },
                connectionEncryption: [
                    plaintext()
                ],
                connectionGater: mockConnectionGater()
            }),
            createLibp2pNode({
                addresses: {
                    listen: [`${relayAddr.toString()}/p2p-circuit`]
                },
                transports: [
                    circuitRelayTransport(),
                    webSockets({
                        filter: filters.all
                    })
                ],
                streamMuxers: [
                    yamux(),
                    mplex()
                ],
                connectionManager: {
                    resolvers: {
                        dnsaddr: resolver
                    }
                },
                connectionEncryption: [
                    plaintext()
                ],
                services: {
                    relay: circuitRelayServer()
                },
                connectionGater: mockConnectionGater()
            })
        ]);
        await Promise.all([
            libp2p.start(),
            remoteLibp2p.start()
        ]);
    });
    afterEach(async () => {
        sinon.restore();
        await Promise.all([libp2p, remoteLibp2p].map(async (n) => {
            if (n != null) {
                await n.stop();
            }
        }));
    });
    it('resolves dnsaddr to ws local address', async () => {
        const peerId = await createEd25519PeerId();
        // ensure remote libp2p creates reservation on relay
        await remoteLibp2p.peerStore.merge(peerId, {
            protocols: [RELAY_V2_HOP_CODEC]
        });
        const remoteId = remoteLibp2p.peerId;
        const dialAddr = multiaddr(`/dnsaddr/remote.libp2p.io/p2p/${remoteId.toString()}`);
        const relayedAddrFetched = multiaddr(relayedAddr(remoteId));
        // Transport spy
        const transport = getTransport(libp2p, 'libp2p/circuit-relay-v2');
        const transportDialSpy = sinon.spy(transport, 'dial');
        // Resolver stub
        resolver.onCall(0).returns(Promise.resolve(getDnsRelayedAddrStub(remoteId)));
        // Dial with address resolve
        const connection = await libp2p.dial(dialAddr);
        expect(connection).to.exist();
        expect(connection.remoteAddr.equals(relayedAddrFetched));
        const dialArgs = transportDialSpy.firstCall.args;
        expect(dialArgs[0].equals(relayedAddrFetched)).to.eql(true);
    });
    it('resolves a dnsaddr recursively', async () => {
        const remoteId = remoteLibp2p.peerId;
        const dialAddr = multiaddr(`/dnsaddr/remote.libp2p.io/p2p/${remoteId.toString()}`);
        const relayedAddrFetched = multiaddr(relayedAddr(remoteId));
        const relayId = await createEd25519PeerId();
        // ensure remote libp2p creates reservation on relay
        await remoteLibp2p.peerStore.merge(relayId, {
            protocols: [RELAY_V2_HOP_CODEC]
        });
        // Transport spy
        const transport = getTransport(libp2p, 'libp2p/circuit-relay-v2');
        const transportDialSpy = sinon.spy(transport, 'dial');
        // Resolver stub
        let firstCall = false;
        resolver.callsFake(async () => {
            if (!firstCall) {
                firstCall = true;
                // Return an array of dnsaddr
                return Promise.resolve(getDnsaddrStub(remoteId));
            }
            return Promise.resolve(getDnsRelayedAddrStub(remoteId));
        });
        // Dial with address resolve
        const connection = await libp2p.dial(dialAddr);
        expect(connection).to.exist();
        expect(connection.remoteAddr.equals(relayedAddrFetched));
        const dialArgs = transportDialSpy.firstCall.args;
        expect(dialArgs[0].equals(relayedAddrFetched)).to.eql(true);
    });
    // TODO: Temporary solution does not resolve dns4/dns6
    // Resolver just returns the received multiaddrs
    it('stops recursive resolve if finds dns4/dns6 and dials it', async () => {
        const remoteId = remoteLibp2p.peerId;
        const dialAddr = multiaddr(`/dnsaddr/remote.libp2p.io/p2p/${remoteId.toString()}`);
        // Stub resolver
        const dnsMa = multiaddr(`/dns4/ams-1.remote.libp2p.io/tcp/443/wss/p2p/${remoteId.toString()}`);
        resolver.returns(Promise.resolve([
            `${dnsMa.toString()}`
        ]));
        const deferred = pDefer();
        // Stub transport
        const transport = getTransport(libp2p, '@libp2p/websockets');
        const stubTransport = sinon.stub(transport, 'dial');
        stubTransport.callsFake(async (multiaddr) => {
            expect(multiaddr.equals(dnsMa)).to.equal(true);
            deferred.resolve();
            return mockConnection(mockMultiaddrConnection(mockDuplex(), peerIdFromString(multiaddr.getPeerId() ?? '')));
        });
        void libp2p.dial(dialAddr);
        await deferred.promise;
    });
    it('resolves a dnsaddr recursively not failing if one address fails to resolve', async () => {
        const remoteId = remoteLibp2p.peerId;
        const dialAddr = multiaddr(`/dnsaddr/remote.libp2p.io/p2p/${remoteId.toString()}`);
        const relayedAddrFetched = multiaddr(relayedAddr(remoteId));
        const relayId = await createEd25519PeerId();
        // ensure remote libp2p creates reservation on relay
        await remoteLibp2p.peerStore.merge(relayId, {
            protocols: [RELAY_V2_HOP_CODEC]
        });
        // Transport spy
        const transport = getTransport(libp2p, 'libp2p/circuit-relay-v2');
        const transportDialSpy = sinon.spy(transport, 'dial');
        // Resolver stub
        resolver.onCall(0).callsFake(async () => Promise.resolve(getDnsaddrStub(remoteId)));
        resolver.onCall(1).callsFake(async () => Promise.reject(new Error()));
        resolver.callsFake(async () => Promise.resolve(getDnsRelayedAddrStub(remoteId)));
        // Dial with address resolve
        const connection = await libp2p.dial(dialAddr);
        expect(connection).to.exist();
        expect(connection.remoteAddr.equals(relayedAddrFetched));
        const dialArgs = transportDialSpy.firstCall.args;
        expect(dialArgs[0].equals(relayedAddrFetched)).to.eql(true);
    });
    it('fails to dial if resolve fails and there are no addresses to dial', async () => {
        const remoteId = remoteLibp2p.peerId;
        const dialAddr = multiaddr(`/dnsaddr/remote.libp2p.io/p2p/${remoteId.toString()}`);
        // Stub resolver
        resolver.returns(Promise.reject(new Error()));
        // Stub transport
        const transport = getTransport(libp2p, '@libp2p/websockets');
        const spy = sinon.spy(transport, 'dial');
        await expect(libp2p.dial(dialAddr))
            .to.eventually.be.rejectedWith(Error)
            .and.to.have.nested.property('.code', ErrorCodes.ERR_NO_VALID_ADDRESSES);
        expect(spy.callCount).to.eql(0);
    });
});
function getTransport(libp2p, tag) {
    const transport = libp2p.components.transportManager.getTransports().find(t => {
        return t[Symbol.toStringTag] === tag;
    });
    if (transport != null) {
        return transport;
    }
    throw new Error(`No transport found for ${tag}`);
}
//# sourceMappingURL=resolver.spec.js.map