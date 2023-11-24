/// <reference types="node" />
import type { Multiaddr } from '@multiformats/multiaddr';
import type { ListenOptions, IpcSocketConnectOpts, TcpSocketConnectOpts } from 'net';
export type NetConfig = ListenOptions | (IpcSocketConnectOpts & TcpSocketConnectOpts);
export declare function multiaddrToNetConfig(addr: Multiaddr, config?: NetConfig): NetConfig;
export declare function getMultiaddrs(proto: 'ip4' | 'ip6', ip: string, port: number): Multiaddr[];
export declare function isAnyAddr(ip: string): boolean;
//# sourceMappingURL=utils.d.ts.map