import isIpPrivate from 'private-ip';
/**
 * Check if a given multiaddr has a private address.
 */
export function isPrivate(ma) {
    try {
        const { address } = ma.nodeAddress();
        return Boolean(isIpPrivate(address));
    }
    catch {
        return true;
    }
}
//# sourceMappingURL=is-private.js.map