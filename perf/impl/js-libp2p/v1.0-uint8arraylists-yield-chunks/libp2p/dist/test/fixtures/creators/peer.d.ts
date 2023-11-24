import { type Libp2pNode } from '../../../src/libp2p.js';
import type { Libp2pOptions } from '../../../src/index.js';
import type { Libp2p, ServiceMap } from '@libp2p/interface';
import type { PeerId } from '@libp2p/interface/peer-id';
export interface CreatePeerOptions<T extends ServiceMap> {
    /**
     * number of peers (default: 1)
     */
    number?: number;
    /**
     * nodes should start (default: true)
     */
    started?: boolean;
    config?: Libp2pOptions<T>;
}
/**
 * Create libp2p nodes.
 */
export declare function createNode<T extends ServiceMap>(options?: CreatePeerOptions<T>): Promise<Libp2pNode<T>>;
export declare function populateAddressBooks(peers: Libp2p[]): Promise<void>;
export interface CreatePeerIdOptions {
    /**
     * Options to pass to the PeerId constructor
     */
    opts?: {
        type?: 'rsa' | 'ed25519';
        bits?: number;
    };
}
/**
 * Create Peer-id
 */
export declare function createPeerId(options?: CreatePeerIdOptions): Promise<PeerId>;
/**
 * Create Peer-ids
 */
export declare function createPeerIds(count: number, options?: Omit<CreatePeerIdOptions, 'fixture'>): Promise<PeerId[]>;
//# sourceMappingURL=peer.d.ts.map