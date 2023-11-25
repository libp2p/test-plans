import { AbstractHandshake, type DecryptedResult } from './abstract-handshake.js';
import type { bytes32, bytes } from '../@types/basic.js';
import type { MessageBuffer, NoiseSession } from '../@types/handshake.js';
import type { KeyPair } from '../@types/libp2p.js';
export declare class XX extends AbstractHandshake {
    private initializeInitiator;
    private initializeResponder;
    private writeMessageA;
    private writeMessageB;
    private writeMessageC;
    private readMessageA;
    private readMessageB;
    private readMessageC;
    initSession(initiator: boolean, prologue: bytes32, s: KeyPair): NoiseSession;
    sendMessage(session: NoiseSession, message: bytes, ephemeral?: KeyPair): MessageBuffer;
    recvMessage(session: NoiseSession, message: MessageBuffer): DecryptedResult;
}
//# sourceMappingURL=xx.d.ts.map