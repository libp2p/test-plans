/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { CodeError, ERR_INVALID_PARAMETERS } from '@libp2p/interface/errors';
import PQueue from 'p-queue';
// Port of lower_bound from https://en.cppreference.com/w/cpp/algorithm/lower_bound
// Used to compute insertion index to keep queue sorted after insertion
function lowerBound(array, value, comparator) {
    let first = 0;
    let count = array.length;
    while (count > 0) {
        const step = Math.trunc(count / 2);
        let it = first + step;
        if (comparator(array[it], value) <= 0) {
            first = ++it;
            count -= step + 1;
        }
        else {
            count = step;
        }
    }
    return first;
}
/**
 * Port of https://github.com/sindresorhus/p-queue/blob/main/source/priority-queue.ts
 * that adds support for filtering jobs by peer id
 */
class PeerPriorityQueue {
    #queue = [];
    enqueue(run, options) {
        const peerId = options?.peerId;
        const priority = options?.priority ?? 0;
        if (peerId == null) {
            throw new CodeError('missing peer id', ERR_INVALID_PARAMETERS);
        }
        const element = {
            priority,
            peerId,
            run
        };
        if (this.size > 0 && this.#queue[this.size - 1].priority >= priority) {
            this.#queue.push(element);
            return;
        }
        const index = lowerBound(this.#queue, element, (a, b) => b.priority - a.priority);
        this.#queue.splice(index, 0, element);
    }
    dequeue() {
        const item = this.#queue.shift();
        return item?.run;
    }
    filter(options) {
        if (options.peerId != null) {
            const peerId = options.peerId;
            return this.#queue.filter((element) => peerId.equals(element.peerId)).map((element) => element.run);
        }
        return this.#queue.filter((element) => element.priority === options.priority).map((element) => element.run);
    }
    get size() {
        return this.#queue.length;
    }
}
/**
 * Extends PQueue to add support for querying queued jobs by peer id
 */
export class PeerJobQueue extends PQueue {
    constructor(options = {}) {
        super({
            ...options,
            queueClass: PeerPriorityQueue
        });
    }
    /**
     * Returns true if this queue has a job for the passed peer id that has not yet
     * started to run
     */
    hasJob(peerId) {
        return this.sizeBy({
            peerId
        }) > 0;
    }
}
//# sourceMappingURL=peer-job-queue.js.map