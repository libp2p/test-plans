import fs from 'fs';
import { yamux } from '@chainsafe/libp2p-yamux';
import { unmarshalPrivateKey } from '@libp2p/crypto/keys';
import { createClient } from '@libp2p/daemon-client';
import { createServer } from '@libp2p/daemon-server';
import { connectInteropTests } from '@libp2p/interop';
import { logger } from '@libp2p/logger';
import { peerIdFromKeys } from '@libp2p/peer-id';
import { tcp } from '@libp2p/tcp';
import { multiaddr } from '@multiformats/multiaddr';
import { execa } from 'execa';
import { path as p2pd } from 'go-libp2p';
import { createLibp2p } from 'libp2p';
import pDefer from 'p-defer';
import { noise } from '../src/index.js';
async function createGoPeer(options) {
    const controlPort = Math.floor(Math.random() * (50000 - 10000 + 1)) + 10000;
    const apiAddr = multiaddr(`/ip4/0.0.0.0/tcp/${controlPort}`);
    const log = logger(`go-libp2p:${controlPort}`);
    const opts = [
        `-listen=${apiAddr.toString()}`,
        '-hostAddrs=/ip4/0.0.0.0/tcp/0'
    ];
    if (options.noise === true) {
        opts.push('-noise=true');
    }
    if (options.key != null) {
        opts.push(`-id=${options.key}`);
    }
    const deferred = pDefer();
    const proc = execa(p2pd(), opts);
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
            listen: ['/ip4/0.0.0.0/tcp/0']
        },
        transports: [tcp()],
        streamMuxers: [yamux()],
        connectionEncryption: [noise()]
    };
    const node = await createLibp2p(opts);
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
    connectInteropTests(factory);
}
main().catch(err => {
    console.error(err); // eslint-disable-line no-console
    process.exit(1);
});
//# sourceMappingURL=interop.js.map