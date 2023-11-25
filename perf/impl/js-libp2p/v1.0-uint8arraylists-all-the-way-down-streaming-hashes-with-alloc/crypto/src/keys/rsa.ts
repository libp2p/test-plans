import crypto from 'crypto'
import { promisify } from 'util'
import { CodeError } from '@libp2p/interface/errors'
import randomBytes from '../random-bytes.js'
import * as utils from './rsa-utils.js'
import type { JWKKeyPair } from './interface.js'
import type { Uint8ArrayList } from 'uint8arraylist'

const keypair = promisify(crypto.generateKeyPair)

export { utils }

export async function generateKey (bits: number): Promise<JWKKeyPair> {
  // @ts-expect-error node types are missing jwk as a format
  const key = await keypair('rsa', {
    modulusLength: bits,
    publicKeyEncoding: { type: 'pkcs1', format: 'jwk' },
    privateKeyEncoding: { type: 'pkcs1', format: 'jwk' }
  })

  return {
    // @ts-expect-error node types are missing jwk as a format
    privateKey: key.privateKey,
    // @ts-expect-error node types are missing jwk as a format
    publicKey: key.publicKey
  }
}

// Takes a jwk key
export async function unmarshalPrivateKey (key: JsonWebKey): Promise<JWKKeyPair> {
  if (key == null) {
    throw new CodeError('Missing key parameter', 'ERR_MISSING_KEY')
  }
  return {
    privateKey: key,
    publicKey: {
      kty: key.kty,
      n: key.n,
      e: key.e
    }
  }
}

export { randomBytes as getRandomValues }

export async function hashAndSign (key: JsonWebKey, msg: Uint8Array | Uint8ArrayList): Promise<Uint8Array> {
  const hash = crypto.createSign('RSA-SHA256')

  if (msg instanceof Uint8Array) {
    hash.update(msg)
  } else {
    for (const buf of msg) {
      hash.update(buf)
    }
  }

  // @ts-expect-error node types are missing jwk as a format
  return hash.sign({ format: 'jwk', key })
}

export async function hashAndVerify (key: JsonWebKey, sig: Uint8Array, msg: Uint8Array | Uint8ArrayList): Promise<boolean> {
  const hash = crypto.createVerify('RSA-SHA256')

  if (msg instanceof Uint8Array) {
    hash.update(msg)
  } else {
    for (const buf of msg) {
      hash.update(buf)
    }
  }

  // @ts-expect-error node types are missing jwk as a format
  return hash.verify({ format: 'jwk', key }, sig)
}

const padding = crypto.constants.RSA_PKCS1_PADDING

export function encrypt (key: JsonWebKey, bytes: Uint8Array | Uint8ArrayList): Uint8Array {
  if (bytes instanceof Uint8Array) {
    // @ts-expect-error node types are missing jwk as a format
    return crypto.publicEncrypt({ format: 'jwk', key, padding }, bytes)
  } else {
    // @ts-expect-error node types are missing jwk as a format
    return crypto.publicEncrypt({ format: 'jwk', key, padding }, bytes.subarray())
  }
}

export function decrypt (key: JsonWebKey, bytes: Uint8Array | Uint8ArrayList): Uint8Array {
  if (bytes instanceof Uint8Array) {
    // @ts-expect-error node types are missing jwk as a format
    return crypto.privateDecrypt({ format: 'jwk', key, padding }, bytes)
  } else {
    // @ts-expect-error node types are missing jwk as a format
    return crypto.privateDecrypt({ format: 'jwk', key, padding }, bytes.subarray())
  }
}

export function keySize (jwk: JsonWebKey): number {
  if (jwk.kty !== 'RSA') {
    throw new CodeError('invalid key type', 'ERR_INVALID_KEY_TYPE')
  } else if (jwk.n == null) {
    throw new CodeError('invalid key modulus', 'ERR_INVALID_KEY_MODULUS')
  }
  const modulus = Buffer.from(jwk.n, 'base64')
  return modulus.length * 8
}
