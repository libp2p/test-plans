import { setMaxListeners } from '@libp2p/interface/events';
import { multiaddr } from '@multiformats/multiaddr';
import { anySignal } from 'any-signal';
/**
 * Resolve multiaddr recursively
 */
export async function resolveMultiaddrs(ma, options) {
    // TODO: recursive logic should live in multiaddr once dns4/dns6 support is in place
    // Now only supporting resolve for dnsaddr
    const resolvableProto = ma.protoNames().includes('dnsaddr');
    // Multiaddr is not resolvable? End recursion!
    if (!resolvableProto) {
        return [ma];
    }
    const resolvedMultiaddrs = await resolveRecord(ma, options);
    const recursiveMultiaddrs = await Promise.all(resolvedMultiaddrs.map(async (nm) => {
        return resolveMultiaddrs(nm, options);
    }));
    const addrs = recursiveMultiaddrs.flat();
    const output = addrs.reduce((array, newM) => {
        if (array.find(m => m.equals(newM)) == null) {
            array.push(newM);
        }
        return array;
    }, ([]));
    options.log('resolved %s to', ma, output.map(ma => ma.toString()));
    return output;
}
/**
 * Resolve a given multiaddr. If this fails, an empty array will be returned
 */
async function resolveRecord(ma, options) {
    try {
        ma = multiaddr(ma.toString()); // Use current multiaddr module
        const multiaddrs = await ma.resolve(options);
        return multiaddrs;
    }
    catch (err) {
        options.log.error(`multiaddr ${ma.toString()} could not be resolved`, err);
        return [];
    }
}
export function combineSignals(...signals) {
    const sigs = [];
    for (const sig of signals) {
        if (sig != null) {
            setMaxListeners(Infinity, sig);
            sigs.push(sig);
        }
    }
    // let any signal abort the dial
    const signal = anySignal(sigs);
    setMaxListeners(Infinity, signal);
    return signal;
}
//# sourceMappingURL=utils.js.map