import { keys } from '@libp2p/crypto';
export async function generateEd25519Keys() {
    return keys.generateKeyPair('Ed25519', 32);
}
export function getKeyPairFromPeerId(peerId) {
    if (peerId.privateKey == null || peerId.publicKey == null) {
        throw new Error('PrivateKey or PublicKey missing from PeerId');
    }
    return {
        privateKey: peerId.privateKey.subarray(0, 32),
        publicKey: peerId.publicKey
    };
}
//# sourceMappingURL=utils.js.map