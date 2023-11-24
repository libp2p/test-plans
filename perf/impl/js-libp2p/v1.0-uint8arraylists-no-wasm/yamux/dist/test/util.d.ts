import { Yamux, YamuxMuxer, type YamuxMuxerInit } from '../src/muxer.js';
import type { Config } from '../src/config.js';
import type { Source, Transform } from 'it-stream-types';
export declare const testConf: Partial<Config>;
/**
 * Yamux must be configured with a client setting `client` to true
 * and a server setting `client` to falsey
 *
 * Since the compliance tests create a dialer and listener,
 * manually alternate setting `client` to true and false
 */
export declare class TestYamux extends Yamux {
    createStreamMuxer(init?: YamuxMuxerInit): YamuxMuxer;
}
export declare function testYamuxMuxer(name: string, client: boolean, conf?: YamuxMuxerInit): YamuxMuxer;
/**
 * Create a transform that can be paused and unpaused
 */
export declare function pauseableTransform<A>(): {
    transform: Transform<Source<A>, AsyncGenerator<A>>;
    pause: () => void;
    unpause: () => void;
};
export interface YamuxFixture extends YamuxMuxer {
    pauseRead: () => void;
    unpauseRead: () => void;
    pauseWrite: () => void;
    unpauseWrite: () => void;
}
export declare function testClientServer(conf?: YamuxMuxerInit): {
    client: YamuxFixture;
    server: YamuxFixture;
};
export declare function timeout(ms: number): Promise<unknown>;
export declare function sleep(ms: number): Promise<unknown>;
//# sourceMappingURL=util.d.ts.map