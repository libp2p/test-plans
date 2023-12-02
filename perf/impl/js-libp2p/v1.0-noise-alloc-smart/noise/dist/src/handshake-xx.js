import { alloc as uint8ArrayAlloc } from 'uint8arrays/alloc';
import { decode0, decode1, decode2, encode0, encode1, encode2 } from './encoder.js';
import { InvalidCryptoExchangeError, UnexpectedPeerError } from './errors.js';
import { XX } from './handshakes/xx.js';
import { logLocalStaticKeys, logLocalEphemeralKeys, logRemoteEphemeralKey, logRemoteStaticKey, logCipherState } from './logger.js';
import { decodePayload, getPeerIdFromPayload, verifySignedPayload } from './utils.js';
export class XXHandshake {
    isInitiator;
    session;
    remotePeer;
    remoteExtensions = { webtransportCerthashes: [] };
    payload;
    connection;
    xx;
    staticKeypair;
    prologue;
    log;
    constructor(components, isInitiator, payload, prologue, crypto, staticKeypair, connection, remotePeer, handshake) {
        this.log = components.logger.forComponent('libp2p:noise:xxhandshake');
        this.isInitiator = isInitiator;
        this.payload = payload;
        this.prologue = prologue;
        this.staticKeypair = staticKeypair;
        this.connection = connection;
        if (remotePeer) {
            this.remotePeer = remotePeer;
        }
        this.xx = handshake ?? new XX(components, crypto);
        this.session = this.xx.initSession(this.isInitiator, this.prologue, this.staticKeypair);
    }
    // stage 0
    async propose() {
        logLocalStaticKeys(this.session.hs.s, this.log);
        if (this.isInitiator) {
            this.log.trace('Stage 0 - Initiator starting to send first message.');
            const messageBuffer = this.xx.sendMessage(this.session, uint8ArrayAlloc(0));
            await this.connection.write(encode0(messageBuffer));
            this.log.trace('Stage 0 - Initiator finished sending first message.');
            logLocalEphemeralKeys(this.session.hs.e, this.log);
        }
        else {
            this.log.trace('Stage 0 - Responder waiting to receive first message...');
            const receivedMessageBuffer = decode0((await this.connection.read()).subarray());
            const { valid } = this.xx.recvMessage(this.session, receivedMessageBuffer);
            if (!valid) {
                throw new InvalidCryptoExchangeError('xx handshake stage 0 validation fail');
            }
            this.log.trace('Stage 0 - Responder received first message.');
            logRemoteEphemeralKey(this.session.hs.re, this.log);
        }
    }
    // stage 1
    async exchange() {
        if (this.isInitiator) {
            this.log.trace('Stage 1 - Initiator waiting to receive first message from responder...');
            const receivedMessageBuffer = decode1((await this.connection.read()).subarray());
            const { plaintext, valid } = this.xx.recvMessage(this.session, receivedMessageBuffer);
            if (!valid) {
                throw new InvalidCryptoExchangeError('xx handshake stage 1 validation fail');
            }
            this.log.trace('Stage 1 - Initiator received the message.');
            logRemoteEphemeralKey(this.session.hs.re, this.log);
            logRemoteStaticKey(this.session.hs.rs, this.log);
            this.log.trace("Initiator going to check remote's signature...");
            try {
                const decodedPayload = decodePayload(plaintext);
                this.remotePeer = this.remotePeer || await getPeerIdFromPayload(decodedPayload);
                await verifySignedPayload(this.session.hs.rs, decodedPayload, this.remotePeer);
                this.setRemoteNoiseExtension(decodedPayload.extensions);
            }
            catch (e) {
                const err = e;
                throw new UnexpectedPeerError(`Error occurred while verifying signed payload: ${err.message}`);
            }
            this.log.trace('All good with the signature!');
        }
        else {
            this.log.trace('Stage 1 - Responder sending out first message with signed payload and static key.');
            const messageBuffer = this.xx.sendMessage(this.session, this.payload);
            await this.connection.write(encode1(messageBuffer));
            this.log.trace('Stage 1 - Responder sent the second handshake message with signed payload.');
            logLocalEphemeralKeys(this.session.hs.e, this.log);
        }
    }
    // stage 2
    async finish() {
        if (this.isInitiator) {
            this.log.trace('Stage 2 - Initiator sending third handshake message.');
            const messageBuffer = this.xx.sendMessage(this.session, this.payload);
            await this.connection.write(encode2(messageBuffer));
            this.log.trace('Stage 2 - Initiator sent message with signed payload.');
        }
        else {
            this.log.trace('Stage 2 - Responder waiting for third handshake message...');
            const receivedMessageBuffer = decode2((await this.connection.read()).subarray());
            const { plaintext, valid } = this.xx.recvMessage(this.session, receivedMessageBuffer);
            if (!valid) {
                throw new InvalidCryptoExchangeError('xx handshake stage 2 validation fail');
            }
            this.log.trace('Stage 2 - Responder received the message, finished handshake.');
            try {
                const decodedPayload = decodePayload(plaintext);
                this.remotePeer = this.remotePeer || await getPeerIdFromPayload(decodedPayload);
                await verifySignedPayload(this.session.hs.rs, decodedPayload, this.remotePeer);
                this.setRemoteNoiseExtension(decodedPayload.extensions);
            }
            catch (e) {
                const err = e;
                throw new UnexpectedPeerError(`Error occurred while verifying signed payload: ${err.message}`);
            }
        }
        logCipherState(this.session, this.log);
    }
    encrypt(plaintext, session) {
        const cs = this.getCS(session);
        return this.xx.encryptWithAd(cs, uint8ArrayAlloc(0), plaintext);
    }
    decrypt(ciphertext, session, dst) {
        const cs = this.getCS(session, false);
        return this.xx.decryptWithAd(cs, uint8ArrayAlloc(0), ciphertext, dst);
    }
    getRemoteStaticKey() {
        return this.session.hs.rs;
    }
    getCS(session, encryption = true) {
        if (!session.cs1 || !session.cs2) {
            throw new InvalidCryptoExchangeError('Handshake not completed properly, cipher state does not exist.');
        }
        if (this.isInitiator) {
            return encryption ? session.cs1 : session.cs2;
        }
        else {
            return encryption ? session.cs2 : session.cs1;
        }
    }
    setRemoteNoiseExtension(e) {
        if (e) {
            this.remoteExtensions = e;
        }
    }
}
//# sourceMappingURL=handshake-xx.js.map