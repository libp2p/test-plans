import { Uint8ArrayList } from 'uint8arraylist';
import { Nonce } from '../nonce.js';
import type { bytes, bytes32 } from '../@types/basic.js';
import type { CipherState, MessageBuffer, SymmetricState } from '../@types/handshake.js';
import type { ICryptoInterface } from '../crypto.js';
export interface DecryptedResult {
    plaintext: Uint8ArrayList | Uint8Array;
    valid: boolean;
}
export interface SplitState {
    cs1: CipherState;
    cs2: CipherState;
}
export declare abstract class AbstractHandshake {
    crypto: ICryptoInterface;
    constructor(crypto: ICryptoInterface);
    encryptWithAd(cs: CipherState, ad: Uint8Array, plaintext: Uint8Array | Uint8ArrayList): Uint8Array | Uint8ArrayList;
    decryptWithAd(cs: CipherState, ad: Uint8Array, ciphertext: Uint8Array | Uint8ArrayList, dst?: Uint8Array): DecryptedResult;
    protected hasKey(cs: CipherState): boolean;
    protected createEmptyKey(): bytes32;
    protected isEmptyKey(k: bytes32): boolean;
    protected encrypt(k: bytes32, n: Nonce, ad: Uint8Array, plaintext: Uint8Array | Uint8ArrayList): Uint8Array | Uint8ArrayList;
    protected encryptAndHash(ss: SymmetricState, plaintext: bytes): Uint8Array | Uint8ArrayList;
    protected decrypt(k: bytes32, n: Nonce, ad: bytes, ciphertext: Uint8Array | Uint8ArrayList, dst?: Uint8Array): DecryptedResult;
    protected decryptAndHash(ss: SymmetricState, ciphertext: Uint8Array | Uint8ArrayList): DecryptedResult;
    protected dh(privateKey: bytes32, publicKey: Uint8Array | Uint8ArrayList): bytes32;
    protected mixHash(ss: SymmetricState, data: Uint8Array | Uint8ArrayList): void;
    protected getHash(a: Uint8Array, b: Uint8Array | Uint8ArrayList): Uint8Array;
    protected mixKey(ss: SymmetricState, ikm: bytes32): void;
    protected initializeKey(k: bytes32): CipherState;
    protected initializeSymmetric(protocolName: string): SymmetricState;
    protected hashProtocolName(protocolName: Uint8Array): bytes32;
    protected split(ss: SymmetricState): SplitState;
    protected writeMessageRegular(cs: CipherState, payload: bytes): MessageBuffer;
    protected readMessageRegular(cs: CipherState, message: MessageBuffer): DecryptedResult;
}
//# sourceMappingURL=abstract-handshake.d.ts.map