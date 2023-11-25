import type { Metrics } from './index.js';
export interface TrackedMapInit {
    name: string;
    metrics: Metrics;
}
export interface CreateTrackedMapInit {
    /**
     * The metric name to use
     */
    name: string;
    /**
     * A metrics implementation
     */
    metrics?: Metrics;
}
export declare function trackedMap<K, V>(config: CreateTrackedMapInit): Map<K, V>;
//# sourceMappingURL=tracked-map.d.ts.map