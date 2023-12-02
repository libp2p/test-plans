import { alloc as uint8ArrayAlloc } from 'uint8arrays/alloc'
import { decode0, decode1, decode2, encode0, encode1, encode2 } from './encoder.js'
import { InvalidCryptoExchangeError, UnexpectedPeerError } from './errors.js'
import { XX } from './handshakes/xx.js'
import {
  logLocalStaticKeys,
  logLocalEphemeralKeys,
  logRemoteEphemeralKey,
  logRemoteStaticKey,
  logCipherState
} from './logger.js'
import {
  decodePayload,
  getPeerIdFromPayload,
  verifySignedPayload
} from './utils.js'
import type { bytes, bytes32 } from './@types/basic.js'
import type { IHandshake } from './@types/handshake-interface.js'
import type { CipherState, NoiseSession } from './@types/handshake.js'
import type { KeyPair } from './@types/libp2p.js'
import type { ICryptoInterface } from './crypto.js'
import type { NoiseComponents } from './index.js'
import type { NoiseExtensions } from './proto/payload.js'
import type { Logger, PeerId } from '@libp2p/interface'
import type { LengthPrefixedStream } from 'it-length-prefixed-stream'
import type { Uint8ArrayList } from 'uint8arraylist'

export class XXHandshake implements IHandshake {
  public isInitiator: boolean
  public session: NoiseSession
  public remotePeer!: PeerId
  public remoteExtensions: NoiseExtensions = { webtransportCerthashes: [] }

  protected payload: bytes
  protected connection: LengthPrefixedStream
  protected xx: XX
  protected staticKeypair: KeyPair

  private readonly prologue: bytes32
  private readonly log: Logger

  constructor (
    components: NoiseComponents,
    isInitiator: boolean,
    payload: bytes,
    prologue: bytes32,
    crypto: ICryptoInterface,
    staticKeypair: KeyPair,
    connection: LengthPrefixedStream,
    remotePeer?: PeerId,
    handshake?: XX
  ) {
    this.log = components.logger.forComponent('libp2p:noise:xxhandshake')
    this.isInitiator = isInitiator
    this.payload = payload
    this.prologue = prologue
    this.staticKeypair = staticKeypair
    this.connection = connection
    if (remotePeer) {
      this.remotePeer = remotePeer
    }
    this.xx = handshake ?? new XX(components, crypto)
    this.session = this.xx.initSession(this.isInitiator, this.prologue, this.staticKeypair)
  }

  // stage 0
  public async propose (): Promise<void> {
    logLocalStaticKeys(this.session.hs.s, this.log)
    if (this.isInitiator) {
      this.log.trace('Stage 0 - Initiator starting to send first message.')
      const messageBuffer = this.xx.sendMessage(this.session, uint8ArrayAlloc(0))
      await this.connection.write(encode0(messageBuffer))
      this.log.trace('Stage 0 - Initiator finished sending first message.')
      logLocalEphemeralKeys(this.session.hs.e, this.log)
    } else {
      this.log.trace('Stage 0 - Responder waiting to receive first message...')
      const receivedMessageBuffer = decode0((await this.connection.read()).subarray())
      const { valid } = this.xx.recvMessage(this.session, receivedMessageBuffer)
      if (!valid) {
        throw new InvalidCryptoExchangeError('xx handshake stage 0 validation fail')
      }
      this.log.trace('Stage 0 - Responder received first message.')
      logRemoteEphemeralKey(this.session.hs.re, this.log)
    }
  }

  // stage 1
  public async exchange (): Promise<void> {
    if (this.isInitiator) {
      this.log.trace('Stage 1 - Initiator waiting to receive first message from responder...')
      const receivedMessageBuffer = decode1((await this.connection.read()).subarray())
      const { plaintext, valid } = this.xx.recvMessage(this.session, receivedMessageBuffer)
      if (!valid) {
        throw new InvalidCryptoExchangeError('xx handshake stage 1 validation fail')
      }
      this.log.trace('Stage 1 - Initiator received the message.')
      logRemoteEphemeralKey(this.session.hs.re, this.log)
      logRemoteStaticKey(this.session.hs.rs, this.log)

      this.log.trace("Initiator going to check remote's signature...")
      try {
        const decodedPayload = decodePayload(plaintext)
        this.remotePeer = this.remotePeer || await getPeerIdFromPayload(decodedPayload)
        await verifySignedPayload(this.session.hs.rs, decodedPayload, this.remotePeer)
        this.setRemoteNoiseExtension(decodedPayload.extensions)
      } catch (e) {
        const err = e as Error
        throw new UnexpectedPeerError(`Error occurred while verifying signed payload: ${err.message}`)
      }
      this.log.trace('All good with the signature!')
    } else {
      this.log.trace('Stage 1 - Responder sending out first message with signed payload and static key.')
      const messageBuffer = this.xx.sendMessage(this.session, this.payload)
      await this.connection.write(encode1(messageBuffer))
      this.log.trace('Stage 1 - Responder sent the second handshake message with signed payload.')
      logLocalEphemeralKeys(this.session.hs.e, this.log)
    }
  }

  // stage 2
  public async finish (): Promise<void> {
    if (this.isInitiator) {
      this.log.trace('Stage 2 - Initiator sending third handshake message.')
      const messageBuffer = this.xx.sendMessage(this.session, this.payload)
      await this.connection.write(encode2(messageBuffer))
      this.log.trace('Stage 2 - Initiator sent message with signed payload.')
    } else {
      this.log.trace('Stage 2 - Responder waiting for third handshake message...')
      const receivedMessageBuffer = decode2((await this.connection.read()).subarray())
      const { plaintext, valid } = this.xx.recvMessage(this.session, receivedMessageBuffer)
      if (!valid) {
        throw new InvalidCryptoExchangeError('xx handshake stage 2 validation fail')
      }
      this.log.trace('Stage 2 - Responder received the message, finished handshake.')

      try {
        const decodedPayload = decodePayload(plaintext)
        this.remotePeer = this.remotePeer || await getPeerIdFromPayload(decodedPayload)
        await verifySignedPayload(this.session.hs.rs, decodedPayload, this.remotePeer)
        this.setRemoteNoiseExtension(decodedPayload.extensions)
      } catch (e) {
        const err = e as Error
        throw new UnexpectedPeerError(`Error occurred while verifying signed payload: ${err.message}`)
      }
    }
    logCipherState(this.session, this.log)
  }

  public encrypt (plaintext: Uint8Array | Uint8ArrayList, session: NoiseSession): Uint8Array | Uint8ArrayList {
    const cs = this.getCS(session)

    return this.xx.encryptWithAd(cs, uint8ArrayAlloc(0), plaintext)
  }

  public decrypt (ciphertext: Uint8Array | Uint8ArrayList, session: NoiseSession, dst?: Uint8Array): { plaintext: Uint8Array | Uint8ArrayList, valid: boolean } {
    const cs = this.getCS(session, false)

    return this.xx.decryptWithAd(cs, uint8ArrayAlloc(0), ciphertext, dst)
  }

  public getRemoteStaticKey (): Uint8Array | Uint8ArrayList {
    return this.session.hs.rs
  }

  private getCS (session: NoiseSession, encryption = true): CipherState {
    if (!session.cs1 || !session.cs2) {
      throw new InvalidCryptoExchangeError('Handshake not completed properly, cipher state does not exist.')
    }

    if (this.isInitiator) {
      return encryption ? session.cs1 : session.cs2
    } else {
      return encryption ? session.cs2 : session.cs1
    }
  }

  protected setRemoteNoiseExtension (e: NoiseExtensions | null | undefined): void {
    if (e) {
      this.remoteExtensions = e
    }
  }
}
