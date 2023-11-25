import { unmarshalPublicKey, unmarshalPrivateKey } from '@libp2p/crypto/keys'
import { peerIdFromKeys } from '@libp2p/peer-id'
import { type Uint8ArrayList, isUint8ArrayList } from 'uint8arraylist'
import { concat as uint8ArrayConcat } from 'uint8arrays/concat'
import { fromString as uint8ArrayFromString } from 'uint8arrays/from-string'
import { type NoiseExtensions, NoiseHandshakePayload } from './proto/payload.js'
import type { bytes } from './@types/basic.js'
import type { PeerId } from '@libp2p/interface/peer-id'

export async function getPayload (
  localPeer: PeerId,
  staticPublicKey: bytes,
  extensions?: NoiseExtensions
): Promise<bytes> {
  const signedPayload = await signPayload(localPeer, getHandshakePayload(staticPublicKey))

  if (localPeer.publicKey == null) {
    throw new Error('PublicKey was missing from local PeerId')
  }

  return createHandshakePayload(
    localPeer.publicKey,
    signedPayload,
    extensions
  )
}

export function createHandshakePayload (
  libp2pPublicKey: Uint8Array,
  signedPayload: Uint8Array,
  extensions?: NoiseExtensions
): bytes {
  return NoiseHandshakePayload.encode({
    identityKey: libp2pPublicKey,
    identitySig: signedPayload,
    extensions: extensions ?? { webtransportCerthashes: [] }
  }).subarray()
}

export async function signPayload (peerId: PeerId, payload: Uint8Array | Uint8ArrayList): Promise<bytes> {
  if (peerId.privateKey == null) {
    throw new Error('PrivateKey was missing from PeerId')
  }

  const privateKey = await unmarshalPrivateKey(peerId.privateKey)

  return privateKey.sign(payload)
}

export async function getPeerIdFromPayload (payload: NoiseHandshakePayload): Promise<PeerId> {
  return peerIdFromKeys(payload.identityKey)
}

export function decodePayload (payload: Uint8Array | Uint8ArrayList): NoiseHandshakePayload {
  return NoiseHandshakePayload.decode(payload)
}

export function getHandshakePayload (publicKey: Uint8Array | Uint8ArrayList): Uint8Array | Uint8ArrayList {
  const prefix = uint8ArrayFromString('noise-libp2p-static-key:')

  if (publicKey instanceof Uint8Array) {
    return uint8ArrayConcat([prefix, publicKey], prefix.length + publicKey.length)
  }

  publicKey.prepend(prefix)

  return publicKey
}

/**
 * Verifies signed payload, throws on any irregularities.
 *
 * @param {bytes} noiseStaticKey - owner's noise static key
 * @param {bytes} payload - decoded payload
 * @param {PeerId} remotePeer - owner's libp2p peer ID
 * @returns {Promise<PeerId>} - peer ID of payload owner
 */
export async function verifySignedPayload (
  noiseStaticKey: Uint8Array | Uint8ArrayList,
  payload: NoiseHandshakePayload,
  remotePeer: PeerId
): Promise<PeerId> {
  // Unmarshaling from PublicKey protobuf
  const payloadPeerId = await peerIdFromKeys(payload.identityKey)
  if (!payloadPeerId.equals(remotePeer)) {
    throw new Error(`Payload identity key ${payloadPeerId.toString()} does not match expected remote peer ${remotePeer.toString()}`)
  }
  const generatedPayload = getHandshakePayload(noiseStaticKey)

  if (payloadPeerId.publicKey == null) {
    throw new Error('PublicKey was missing from PeerId')
  }

  if (payload.identitySig == null) {
    throw new Error('Signature was missing from message')
  }

  const publicKey = unmarshalPublicKey(payloadPeerId.publicKey)

  const valid = await publicKey.verify(generatedPayload, payload.identitySig)

  if (!valid) {
    throw new Error("Static key doesn't match to peer that signed payload!")
  }

  return payloadPeerId
}

export function isValidPublicKey (pk: Uint8Array | Uint8ArrayList): boolean {
  if (!(pk instanceof Uint8Array) && !(isUint8ArrayList(pk))) {
    return false
  }

  if (pk.byteLength !== 32) {
    return false
  }

  return true
}
