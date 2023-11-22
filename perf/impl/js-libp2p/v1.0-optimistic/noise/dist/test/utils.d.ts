import type { KeyPair } from '../src/@types/libp2p.js';
import type { PrivateKey } from '@libp2p/interface/keys';
import type { PeerId } from '@libp2p/interface/peer-id';
export declare function generateEd25519Keys(): Promise<PrivateKey>;
export declare function getKeyPairFromPeerId(peerId: PeerId): KeyPair;
//# sourceMappingURL=utils.d.ts.map