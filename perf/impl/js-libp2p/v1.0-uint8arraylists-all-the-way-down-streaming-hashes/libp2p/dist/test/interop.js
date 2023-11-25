import fs from 'fs';
import { gossipsub } from '@chainsafe/libp2p-gossipsub';
import { noise } from '@chainsafe/libp2p-noise';
import { yamux } from '@chainsafe/libp2p-yamux';
import { circuitRelayServer, circuitRelayTransport } from '@libp2p/circuit-relay-v2';
import { unmarshalPrivateKey } from '@libp2p/crypto/keys';
import { createClient } from '@libp2p/daemon-client';
import { createServer } from '@libp2p/daemon-server';
import { floodsub } from '@libp2p/floodsub';
import { identify } from '@libp2p/identify';
import { contentRouting } from '@libp2p/interface/content-routing';
import { peerDiscovery } from '@libp2p/interface/peer-discovery';
import { peerRouting } from '@libp2p/interface/peer-routing';
import { interopTests } from '@libp2p/interop';
import { kadDHT } from '@libp2p/kad-dht';
import { logger } from '@libp2p/logger';
import { mplex } from '@libp2p/mplex';
import { peerIdFromKeys } from '@libp2p/peer-id';
import { tcp } from '@libp2p/tcp';
import { multiaddr } from '@multiformats/multiaddr';
import { execa } from 'execa';
import { path as p2pd } from 'go-libp2p';
import pDefer from 'p-defer';
import { createLibp2p } from '../src/index.js';
/**
 * @packageDocumentation
 *
 * To enable debug logging, run the tests with the following env vars:
 *
 * ```console
 * DEBUG=libp2p*,go-libp2p:* npm run test:interop
 * ```
 */
async function createGoPeer(options) {
    const controlPort = Math.floor(Math.random() * (50000 - 10000 + 1)) + 10000;
    const apiAddr = multiaddr(`/ip4/127.0.0.1/tcp/${controlPort}`);
    const log = logger(`go-libp2p:${controlPort}`);
    const opts = [
        `-listen=${apiAddr.toString()}`
    ];
    if (options.noListen === true) {
        opts.push('-noListenAddrs');
    }
    else {
        opts.push('-hostAddrs=/ip4/127.0.0.1/tcp/0');
    }
    if (options.noise === true) {
        opts.push('-noise=true');
    }
    if (options.dht === true) {
        opts.push('-dhtServer');
    }
    if (options.relay === true) {
        opts.push('-relay');
    }
    if (options.pubsub === true) {
        opts.push('-pubsub');
    }
    if (options.pubsubRouter != null) {
        opts.push(`-pubsubRouter=${options.pubsubRouter}`);
    }
    if (options.key != null) {
        opts.push(`-id=${options.key}`);
    }
    if (options.muxer === 'mplex') {
        opts.push('-muxer=mplex');
    }
    else {
        opts.push('-muxer=yamux');
    }
    const deferred = pDefer();
    const proc = execa(p2pd(), opts, {
        env: {
            GOLOG_LOG_LEVEL: 'debug'
        }
    });
    proc.stdout?.on('data', (buf) => {
        const str = buf.toString();
        log(str);
        // daemon has started
        if (str.includes('Control socket:')) {
            deferred.resolve();
        }
    });
    proc.stderr?.on('data', (buf) => {
        log.error(buf.toString());
    });
    await deferred.promise;
    return {
        client: createClient(apiAddr),
        stop: async () => {
            proc.kill();
        }
    };
}
async function createJsPeer(options) {
    let peerId;
    if (options.key != null) {
        const keyFile = fs.readFileSync(options.key);
        const privateKey = await unmarshalPrivateKey(keyFile);
        peerId = await peerIdFromKeys(privateKey.public.bytes, privateKey.bytes);
    }
    const opts = {
        peerId,
        addresses: {
            listen: options.noListen === true ? [] : ['/ip4/127.0.0.1/tcp/0']
        },
        transports: [tcp(), circuitRelayTransport()],
        streamMuxers: [],
        connectionEncryption: [noise()],
        connectionManager: {
            minConnections: 0
        }
    };
    const services = {
        identify: identify()
    };
    if (options.muxer === 'mplex') {
        opts.streamMuxers?.push(mplex());
    }
    else {
        opts.streamMuxers?.push(yamux());
    }
    if (options.pubsub === true) {
        if (options.pubsubRouter === 'floodsub') {
            services.pubsub = floodsub();
        }
        else {
            services.pubsub = gossipsub();
        }
    }
    if (options.relay === true) {
        services.relay = circuitRelayServer();
    }
    if (options.dht === true) {
        services.dht = (components) => {
            const dht = kadDHT({
                clientMode: false
            })(components);
            // go-libp2p-daemon only has the older single-table DHT instead of the dual
            // lan/wan version found in recent go-ipfs versions. unfortunately it's been
            // abandoned so here we simulate the older config with the js implementation
            const lan = dht.lan;
            const protocol = '/ipfs/kad/1.0.0';
            lan.protocol = protocol;
            lan.network.protocol = protocol;
            lan.topologyListener.protocol = protocol;
            Object.defineProperties(lan, {
                [contentRouting]: {
                    get() {
                        return dht[contentRouting];
                    }
                },
                [peerRouting]: {
                    get() {
                        return dht[peerRouting];
                    }
                },
                [peerDiscovery]: {
                    get() {
                        return dht[peerDiscovery];
                    }
                }
            });
            return lan;
        };
    }
    const node = await createLibp2p({
        ...opts,
        services
    });
    const server = createServer(multiaddr('/ip4/0.0.0.0/tcp/0'), node);
    await server.start();
    return {
        client: createClient(server.getMultiaddr()),
        stop: async () => {
            await server.stop();
            await node.stop();
        }
    };
}
async function main() {
    const factory = {
        async spawn(options) {
            if (options.type === 'go') {
                return createGoPeer(options);
            }
            return createJsPeer(options);
        }
    };
    await interopTests(factory);
}
main().catch(err => {
    console.error(err); // eslint-disable-line no-console
    process.exit(1);
});
//# sourceMappingURL=interop.js.map