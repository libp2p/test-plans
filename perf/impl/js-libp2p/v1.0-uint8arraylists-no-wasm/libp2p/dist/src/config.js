import { CodeError } from '@libp2p/interface/errors';
import { FaultTolerance } from '@libp2p/interface/transport';
import { defaultAddressSort } from '@libp2p/utils/address-sort';
import { dnsaddrResolver } from '@multiformats/multiaddr/resolvers';
import mergeOptions from 'merge-options';
import { codes, messages } from './errors.js';
const DefaultConfig = {
    addresses: {
        listen: [],
        announce: [],
        noAnnounce: [],
        announceFilter: (multiaddrs) => multiaddrs
    },
    connectionManager: {
        resolvers: {
            dnsaddr: dnsaddrResolver
        },
        addressSorter: defaultAddressSort
    },
    transportManager: {
        faultTolerance: FaultTolerance.FATAL_ALL
    }
};
export function validateConfig(opts) {
    const resultingOptions = mergeOptions(DefaultConfig, opts);
    if (resultingOptions.transports == null || resultingOptions.transports.length < 1) {
        throw new CodeError(messages.ERR_TRANSPORTS_REQUIRED, codes.ERR_TRANSPORTS_REQUIRED);
    }
    if (resultingOptions.connectionProtector === null && globalThis.process?.env?.LIBP2P_FORCE_PNET != null) { // eslint-disable-line no-undef
        throw new CodeError(messages.ERR_PROTECTOR_REQUIRED, codes.ERR_PROTECTOR_REQUIRED);
    }
    return resultingOptions;
}
//# sourceMappingURL=config.js.map