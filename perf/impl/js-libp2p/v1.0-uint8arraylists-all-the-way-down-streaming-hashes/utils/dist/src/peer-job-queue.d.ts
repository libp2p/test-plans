import PQueue from 'p-queue';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { QueueAddOptions, Options, Queue } from 'p-queue';
interface RunFunction {
    (): Promise<unknown>;
}
export interface PeerPriorityQueueOptions extends QueueAddOptions {
    peerId: PeerId;
}
/**
 * Port of https://github.com/sindresorhus/p-queue/blob/main/source/priority-queue.ts
 * that adds support for filtering jobs by peer id
 */
declare class PeerPriorityQueue implements Queue<RunFunction, PeerPriorityQueueOptions> {
    #private;
    enqueue(run: RunFunction, options?: Partial<PeerPriorityQueueOptions>): void;
    dequeue(): RunFunction | undefined;
    filter(options: Readonly<Partial<PeerPriorityQueueOptions>>): RunFunction[];
    get size(): number;
}
/**
 * Extends PQueue to add support for querying queued jobs by peer id
 */
export declare class PeerJobQueue extends PQueue<PeerPriorityQueue, PeerPriorityQueueOptions> {
    constructor(options?: Options<PeerPriorityQueue, PeerPriorityQueueOptions>);
    /**
     * Returns true if this queue has a job for the passed peer id that has not yet
     * started to run
     */
    hasJob(peerId: PeerId): boolean;
}
export {};
//# sourceMappingURL=peer-job-queue.d.ts.map