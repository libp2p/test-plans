/* eslint-env mocha */
import { EventTypes } from '@libp2p/kad-dht';
import { peerIdFromString } from '@libp2p/peer-id';
import { multiaddr } from '@multiformats/multiaddr';
import { expect } from 'aegir/chai';
import all from 'it-all';
import drain from 'it-drain';
import { CID } from 'multiformats/cid';
import pDefer from 'p-defer';
import sinon from 'sinon';
import { stubInterface } from 'sinon-ts';
import { createLibp2p } from '../../src/index.js';
import { createBaseOptions } from '../fixtures/base-options.js';
import { createNode, createPeerId, populateAddressBooks } from '../fixtures/creators/peer.js';
import { createRoutingOptions } from './utils.js';
describe('content-routing', () => {
    describe('no routers', () => {
        let node;
        before(async () => {
            node = await createNode({
                config: createBaseOptions()
            });
        });
        after(async () => { await node.stop(); });
        it('.findProviders should return an error', async () => {
            try {
                // @ts-expect-error invalid params
                for await (const _ of node.contentRouting.findProviders('a cid')) { } // eslint-disable-line
                throw new Error('.findProviders should return an error');
            }
            catch (err) {
                expect(err).to.exist();
                expect(err.code).to.equal('ERR_NO_ROUTERS_AVAILABLE');
            }
        });
        it('.provide should return an error', async () => {
            // @ts-expect-error invalid params
            await expect(node.contentRouting.provide('a cid'))
                .to.eventually.be.rejected()
                .and.to.have.property('code', 'ERR_NO_ROUTERS_AVAILABLE');
        });
    });
    describe('via dht router', () => {
        const number = 5;
        let nodes;
        before(async () => {
            nodes = await Promise.all([
                createLibp2p(createRoutingOptions()),
                createLibp2p(createRoutingOptions()),
                createLibp2p(createRoutingOptions()),
                createLibp2p(createRoutingOptions()),
                createLibp2p(createRoutingOptions())
            ]);
            await populateAddressBooks(nodes);
            // Ring dial
            await Promise.all(nodes.map(async (peer, i) => peer.dial(nodes[(i + 1) % number].peerId)));
        });
        afterEach(() => {
            sinon.restore();
        });
        after(async () => Promise.all(nodes.map(async (n) => { await n.stop(); })));
        it('should use the nodes dht to provide', async () => {
            const deferred = pDefer();
            if (nodes[0].services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(nodes[0].services.dht, 'provide').callsFake(async function* () {
                deferred.resolve();
            });
            void nodes[0].contentRouting.provide(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB'));
            return deferred.promise;
        });
        it('should use the nodes dht to find providers', async () => {
            const deferred = pDefer();
            if (nodes[0].services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(nodes[0].services.dht, 'findProviders').callsFake(async function* () {
                yield {
                    from: nodes[0].peerId,
                    type: EventTypes.PROVIDER,
                    name: 'PROVIDER',
                    providers: [{
                            id: nodes[0].peerId,
                            multiaddrs: [],
                            protocols: []
                        }]
                };
                deferred.resolve();
            });
            await drain(nodes[0].contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB')));
            return deferred.promise;
        });
    });
    describe('via delegate router', () => {
        let node;
        let delegate;
        beforeEach(async () => {
            delegate = stubInterface();
            delegate.provide.returns(Promise.resolve());
            delegate.findProviders.returns(async function* () { }());
            node = await createNode({
                config: createBaseOptions({
                    contentRouters: [
                        () => delegate
                    ]
                })
            });
        });
        afterEach(async () => {
            if (node != null) {
                await node.stop();
            }
            sinon.restore();
        });
        it('should use the delegate router to provide', async () => {
            const deferred = pDefer();
            delegate.provide.callsFake(async () => {
                deferred.resolve();
            });
            void node.contentRouting.provide(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB'));
            return deferred.promise;
        });
        it('should use the delegate router to find providers', async () => {
            const deferred = pDefer();
            delegate.findProviders.returns(async function* () {
                yield {
                    id: node.peerId,
                    multiaddrs: [],
                    protocols: []
                };
                deferred.resolve();
            }());
            await drain(node.contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB')));
            return deferred.promise;
        });
        it('should be able to register as a provider', async () => {
            const cid = CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB');
            await node.contentRouting.provide(cid);
            expect(delegate.provide.calledWith(cid)).to.equal(true);
        });
        it('should handle errors when registering as a provider', async () => {
            const cid = CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB');
            delegate.provide.withArgs(cid).throws(new Error('Could not provide'));
            await expect(node.contentRouting.provide(cid))
                .to.eventually.be.rejected()
                .with.property('message', 'Could not provide');
        });
        it('should be able to find providers', async () => {
            const cid = CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB');
            const provider = 'QmZNgCqZCvTsi3B4Vt7gsSqpkqDpE7M2Y9TDmEhbDb4ceF';
            delegate.findProviders.withArgs(cid).returns(async function* () {
                yield {
                    id: peerIdFromString(provider),
                    multiaddrs: [
                        multiaddr('/ip4/0.0.0.0/tcp/0')
                    ],
                    protocols: []
                };
            }());
            const providers = await all(node.contentRouting.findProviders(cid));
            expect(providers).to.have.length(1);
            expect(providers[0].id.toString()).to.equal(provider);
        });
        it('should handle errors when finding providers', async () => {
            const cid = CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB');
            delegate.findProviders.withArgs(cid).throws(new Error('Could not find providers'));
            await expect(drain(node.contentRouting.findProviders(cid)))
                .to.eventually.be.rejected()
                .with.property('message', 'Could not find providers');
        });
    });
    describe('via dht and delegate routers', () => {
        let node;
        let delegate;
        beforeEach(async () => {
            delegate = stubInterface();
            delegate.provide.returns(Promise.resolve());
            delegate.findProviders.returns(async function* () { }());
            node = await createNode({
                config: createRoutingOptions({
                    contentRouters: [
                        () => delegate
                    ]
                })
            });
        });
        afterEach(() => {
            sinon.restore();
        });
        afterEach(async () => { await node.stop(); });
        it('should store the multiaddrs of a peer', async () => {
            const providerPeerId = await createPeerId();
            const result = {
                id: providerPeerId,
                multiaddrs: [
                    multiaddr('/ip4/123.123.123.123/tcp/49320')
                ]
            };
            if (node.services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(node.services.dht, 'findProviders').callsFake(async function* () { });
            delegate.findProviders.callsFake(async function* () {
                yield result;
            });
            expect(await node.peerStore.has(providerPeerId)).to.not.be.ok();
            await drain(node.contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB')));
            await expect(node.peerStore.get(providerPeerId)).to.eventually.have.property('addresses').that.deep.include({
                isCertified: false,
                multiaddr: result.multiaddrs[0]
            });
        });
        it('should not wait for routing findProviders to finish before returning results', async () => {
            const providerPeerId = await createPeerId();
            const result = {
                id: providerPeerId,
                multiaddrs: [
                    multiaddr('/ip4/123.123.123.123/tcp/49320')
                ],
                protocols: []
            };
            if (node.services.dht == null) {
                throw new Error('DHT was not configured');
            }
            const defer = pDefer();
            sinon.stub(node.services.dht, 'findProviders').callsFake(async function* () {
                await defer.promise;
            });
            delegate.findProviders.callsFake(async function* () {
                yield result;
                await defer.promise;
            });
            for await (const provider of node.contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB'))) {
                expect(provider.id).to.deep.equal(providerPeerId);
                defer.resolve();
            }
        });
        it('should dedupe results', async () => {
            const providerPeerId = await createPeerId();
            const result = {
                id: providerPeerId,
                multiaddrs: [
                    multiaddr('/ip4/123.123.123.123/tcp/49320')
                ],
                protocols: []
            };
            if (node.services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(node.services.dht, 'findProviders').callsFake(async function* () {
                yield {
                    from: providerPeerId,
                    type: EventTypes.PROVIDER,
                    name: 'PROVIDER',
                    providers: [
                        result
                    ]
                };
            });
            delegate.findProviders.callsFake(async function* () {
                yield result;
            });
            const results = await all(node.contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB')));
            expect(results).to.be.an('array').with.lengthOf(1).that.deep.equals([result]);
        });
        it('should combine multiaddrs when different addresses are returned by different content routers', async () => {
            const providerPeerId = await createPeerId();
            const result1 = {
                id: providerPeerId,
                multiaddrs: [
                    multiaddr('/ip4/123.123.123.123/tcp/49320')
                ],
                protocols: []
            };
            const result2 = {
                id: providerPeerId,
                multiaddrs: [
                    multiaddr('/ip4/213.213.213.213/tcp/2344')
                ],
                protocols: []
            };
            if (node.services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(node.services.dht, 'findProviders').callsFake(async function* () {
                yield {
                    from: providerPeerId,
                    type: EventTypes.PROVIDER,
                    name: 'PROVIDER',
                    providers: [
                        result1
                    ]
                };
            });
            delegate.findProviders.callsFake(async function* () {
                yield result2;
            });
            await drain(node.contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB')));
            await expect(node.peerStore.get(providerPeerId)).to.eventually.have.property('addresses').that.deep.include({
                isCertified: false,
                multiaddr: result1.multiaddrs[0]
            }).and.to.deep.include({
                isCertified: false,
                multiaddr: result2.multiaddrs[0]
            });
        });
        it('should use both the dht and delegate router to provide', async () => {
            const dhtDeferred = pDefer();
            const delegatedDeferred = pDefer();
            if (node.services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(node.services.dht, 'provide').callsFake(async function* () {
                dhtDeferred.resolve();
            });
            delegate.provide.callsFake(async function () {
                delegatedDeferred.resolve();
            });
            await node.contentRouting.provide(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB'));
            await Promise.all([
                dhtDeferred.promise,
                delegatedDeferred.promise
            ]);
        });
        it('should use the dht if the delegate fails to find providers', async () => {
            const providerPeerId = await createPeerId();
            const results = [{
                    id: providerPeerId,
                    multiaddrs: [],
                    protocols: []
                }];
            if (node.services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(node.services.dht, 'findProviders').callsFake(async function* () {
                yield {
                    from: providerPeerId,
                    type: EventTypes.PROVIDER,
                    name: 'PROVIDER',
                    providers: [
                        results[0]
                    ]
                };
            });
            delegate.findProviders.callsFake(async function* () {
            });
            const providers = [];
            for await (const prov of node.contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB'))) {
                providers.push(prov);
            }
            expect(providers).to.have.length.above(0);
            expect(providers).to.eql(results);
        });
        it('should use the delegate if the dht fails to find providers', async () => {
            const providerPeerId = await createPeerId();
            const results = [{
                    id: providerPeerId,
                    multiaddrs: [],
                    protocols: []
                }];
            if (node.services.dht == null) {
                throw new Error('DHT was not configured');
            }
            sinon.stub(node.services.dht, 'findProviders').callsFake(async function* () { });
            delegate.findProviders.callsFake(async function* () {
                yield results[0];
            });
            const providers = [];
            for await (const prov of node.contentRouting.findProviders(CID.parse('QmU621oD8AhHw6t25vVyfYKmL9VV3PTgc52FngEhTGACFB'))) {
                providers.push(prov);
            }
            expect(providers).to.have.length.above(0);
            expect(providers).to.eql(results);
        });
    });
});
//# sourceMappingURL=content-routing.node.js.map