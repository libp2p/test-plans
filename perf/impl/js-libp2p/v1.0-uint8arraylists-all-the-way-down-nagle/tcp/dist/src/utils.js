import os from 'os';
import path from 'path';
import { multiaddr } from '@multiformats/multiaddr';
const ProtoFamily = { ip4: 'IPv4', ip6: 'IPv6' };
export function multiaddrToNetConfig(addr, config = {}) {
    const listenPath = addr.getPath();
    // unix socket listening
    if (listenPath != null) {
        if (os.platform() === 'win32') {
            // Use named pipes on Windows systems.
            return { path: path.join('\\\\.\\pipe\\', listenPath) };
        }
        else {
            return { path: listenPath };
        }
    }
    // tcp listening
    return { ...config, ...addr.toOptions() };
}
export function getMultiaddrs(proto, ip, port) {
    const toMa = (ip) => multiaddr(`/${proto}/${ip}/tcp/${port}`);
    return (isAnyAddr(ip) ? getNetworkAddrs(ProtoFamily[proto]) : [ip]).map(toMa);
}
export function isAnyAddr(ip) {
    return ['0.0.0.0', '::'].includes(ip);
}
const networks = os.networkInterfaces();
function getNetworkAddrs(family) {
    const addresses = [];
    for (const [, netAddrs] of Object.entries(networks)) {
        if (netAddrs != null) {
            for (const netAddr of netAddrs) {
                if (netAddr.family === family) {
                    addresses.push(netAddr.address);
                }
            }
        }
    }
    return addresses;
}
//# sourceMappingURL=utils.js.map