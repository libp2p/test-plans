import type { ConnectionGater } from '@libp2p/interface/connection-gater';
/**
 * Returns a connection gater that disallows dialling private addresses by
 * default. Browsers are severely limited in their resource usage so don't
 * waste time trying to dial undiallable addresses.
 */
export declare function connectionGater(gater?: ConnectionGater): ConnectionGater;
//# sourceMappingURL=connection-gater.browser.d.ts.map