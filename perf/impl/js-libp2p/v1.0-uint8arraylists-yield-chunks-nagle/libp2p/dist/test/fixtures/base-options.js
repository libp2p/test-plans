import { yamux } from '@chainsafe/libp2p-yamux';
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2';
import { mplex } from '@libp2p/mplex';
import { plaintext } from '@libp2p/plaintext';
import { tcp } from '@libp2p/tcp';
import { webSockets } from '@libp2p/websockets';
import * as filters from '@libp2p/websockets/filters';
import mergeOptions from 'merge-options';
export function createBaseOptions(...overrides) {
    const options = {
        addresses: {
            listen: [`${process.env.RELAY_MULTIADDR}/p2p-circuit`]
        },
        transports: [
            tcp(),
            webSockets({
                filter: filters.all
            }),
            circuitRelayTransport()
        ],
        streamMuxers: [
            yamux(),
            mplex()
        ],
        connectionEncryption: [
            plaintext()
        ]
    };
    return mergeOptions(options, ...overrides);
}
//# sourceMappingURL=base-options.js.map