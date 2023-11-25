import type { StreamMuxer, StreamMuxerInit } from '@libp2p/interface/stream-muxer';
import type { Source, Transform } from 'it-stream-types';
export declare function testYamuxMuxer(name: string, client: boolean, conf?: StreamMuxerInit): StreamMuxer;
/**
 * Create a transform that can be paused and unpaused
 */
export declare function pauseableTransform<A>(): {
    transform: Transform<Source<A>, AsyncGenerator<A>>;
    pause: () => void;
    unpause: () => void;
};
export declare function testClientServer(conf?: StreamMuxerInit): {
    client: StreamMuxer & {
        pauseRead: () => void;
        unpauseRead: () => void;
        pauseWrite: () => void;
        unpauseWrite: () => void;
    };
    server: StreamMuxer & {
        pauseRead: () => void;
        unpauseRead: () => void;
        pauseWrite: () => void;
        unpauseWrite: () => void;
    };
};
export declare function timeout(ms: number): Promise<unknown>;
export declare function sleep(ms: number): Promise<unknown>;
//# sourceMappingURL=mplex.util.d.ts.map