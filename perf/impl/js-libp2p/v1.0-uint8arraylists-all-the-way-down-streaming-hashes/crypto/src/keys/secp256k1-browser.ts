import { CodeError } from '@libp2p/interface/errors'
import { secp256k1 as secp } from '@noble/curves/secp256k1'
import { sha256 } from 'multiformats/hashes/sha2'
import type { Uint8ArrayList } from 'uint8arraylist'

const PRIVATE_KEY_BYTE_LENGTH = 32

export { PRIVATE_KEY_BYTE_LENGTH as privateKeyLength }

export function generateKey (): Uint8Array {
  return secp.utils.randomPrivateKey()
}

/**
 * Hash and sign message with private key
 */
export async function hashAndSign (key: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<Uint8Array> {
  const { digest } = await sha256.digest(msg instanceof Uint8Array ? msg : msg.subarray())
  try {
    const signature = secp.sign(digest, key)
    return signature.toDERRawBytes()
  } catch (err) {
    throw new CodeError(String(err), 'ERR_INVALID_INPUT')
  }
}

/**
 * Hash message and verify signature with public key
 */
export async function hashAndVerify (key: Uint8Array, sig: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<boolean> {
  try {
    const { digest } = await sha256.digest(msg instanceof Uint8Array ? msg : msg.subarray())
    return secp.verify(sig, digest, key)
  } catch (err) {
    throw new CodeError(String(err), 'ERR_INVALID_INPUT')
  }
}

export function compressPublicKey (key: Uint8Array): Uint8Array {
  const point = secp.ProjectivePoint.fromHex(key).toRawBytes(true)
  return point
}

export function decompressPublicKey (key: Uint8Array): Uint8Array {
  const point = secp.ProjectivePoint.fromHex(key).toRawBytes(false)
  return point
}

export function validatePrivateKey (key: Uint8Array): void {
  try {
    secp.getPublicKey(key, true)
  } catch (err) {
    throw new CodeError(String(err), 'ERR_INVALID_PRIVATE_KEY')
  }
}

export function validatePublicKey (key: Uint8Array): void {
  try {
    secp.ProjectivePoint.fromHex(key)
  } catch (err) {
    throw new CodeError(String(err), 'ERR_INVALID_PUBLIC_KEY')
  }
}

export function computePublicKey (privateKey: Uint8Array): Uint8Array {
  try {
    return secp.getPublicKey(privateKey, true)
  } catch (err) {
    throw new CodeError(String(err), 'ERR_INVALID_PRIVATE_KEY')
  }
}
