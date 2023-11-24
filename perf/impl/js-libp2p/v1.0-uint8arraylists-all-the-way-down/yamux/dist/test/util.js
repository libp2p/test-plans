import { logger } from '@libp2p/logger';
import { duplexPair } from 'it-pair/duplex';
import { pipe } from 'it-pipe';
import { Yamux, YamuxMuxer } from '../src/muxer.js';
import { Uint8ArrayList } from 'uint8arraylist';
const isClient = (() => {
    let client = false;
    return () => {
        const isClient = !client;
        client = isClient;
        return isClient;
    };
})();
export const testConf = {
    enableKeepAlive: false
};
/**
 * Yamux must be configured with a client setting `client` to true
 * and a server setting `client` to falsey
 *
 * Since the compliance tests create a dialer and listener,
 * manually alternate setting `client` to true and false
 */
export class TestYamux extends Yamux {
    createStreamMuxer(init) {
        const client = isClient();
        return super.createStreamMuxer({ ...testConf, ...init, direction: client ? 'outbound' : 'inbound', log: logger(`libp2p:yamux${client ? 1 : 2}`) });
    }
}
export function testYamuxMuxer(name, client, conf = {}) {
    return new YamuxMuxer({
        ...testConf,
        ...conf,
        direction: client ? 'outbound' : 'inbound',
        log: logger(name)
    });
}
/**
 * Create a transform that can be paused and unpaused
 */
export function pauseableTransform() {
    let resolvePausePromise;
    let pausePromise;
    const unpause = () => {
        resolvePausePromise?.(null);
    };
    const pause = () => {
        pausePromise = new Promise(resolve => {
            resolvePausePromise = resolve;
        });
    };
    const transform = async function* (source) {
        for await (const d of source) {
            if (pausePromise !== undefined) {
                await pausePromise;
                pausePromise = undefined;
                resolvePausePromise = undefined;
            }
            yield d;
        }
    };
    return { transform, pause, unpause };
}
export function testClientServer(conf = {}) {
    const pair = duplexPair();
    const client = testYamuxMuxer('libp2p:yamux:client', true, conf);
    const server = testYamuxMuxer('libp2p:yamux:server', false, conf);
    const clientReadTransform = pauseableTransform();
    const clientWriteTransform = pauseableTransform();
    const serverReadTransform = pauseableTransform();
    const serverWriteTransform = pauseableTransform();
    void pipe(pair[0], clientReadTransform.transform, client, clientWriteTransform.transform, pair[0]);
    void pipe(pair[1], serverReadTransform.transform, server, serverWriteTransform.transform, pair[1]);
    return {
        client: Object.assign(client, {
            pauseRead: clientReadTransform.pause,
            unpauseRead: clientReadTransform.unpause,
            pauseWrite: clientWriteTransform.pause,
            unpauseWrite: clientWriteTransform.unpause
        }),
        server: Object.assign(server, {
            pauseRead: serverReadTransform.pause,
            unpauseRead: serverReadTransform.unpause,
            pauseWrite: serverWriteTransform.pause,
            unpauseWrite: serverWriteTransform.unpause
        })
    };
}
export async function timeout(ms) {
    return new Promise((_resolve, reject) => setTimeout(() => { reject(new Error(`timeout after ${ms}ms`)); }, ms));
}
export async function sleep(ms) {
    return new Promise(resolve => setTimeout(() => { resolve(ms); }, ms));
}
//# sourceMappingURL=util.js.map