import type { Counter, Metrics } from '@libp2p/interface/metrics';
export type MetricsRegistry = Record<string, Counter>;
export declare function registerMetrics(metrics: Metrics): MetricsRegistry;
//# sourceMappingURL=metrics.d.ts.map