import crypto from 'node:crypto'
import { newInstance, ChaCha20Poly1305 } from '@chainsafe/as-chacha20poly1305'
import { digest } from '@chainsafe/as-sha256'
import { concat as uint8ArrayConcat } from 'uint8arrays/concat'
import { isElectronMain } from 'wherearewe'
import { pureJsCrypto } from './js.js'
import type { KeyPair } from '../@types/libp2p.js'
import type { ICryptoInterface } from '../crypto.js'

const ctx = newInstance()
const asImpl = new ChaCha20Poly1305(ctx)
const CHACHA_POLY1305 = 'chacha20-poly1305'
const nodeCrypto: Pick<ICryptoInterface, 'hashSHA256' | 'chaCha20Poly1305Encrypt' | 'chaCha20Poly1305Decrypt'> = {
  hashSHA256 (data) {
    return crypto.createHash('sha256').update(data).digest()
  },

  chaCha20Poly1305Encrypt (plaintext, nonce, ad, k) {
    const cipher = crypto.createCipheriv(CHACHA_POLY1305, k, nonce, {
      authTagLength: 16
    })
    cipher.setAAD(ad, { plaintextLength: plaintext.byteLength })
    const updated = cipher.update(plaintext)
    const final = cipher.final()
    const tag = cipher.getAuthTag()

    const encrypted = Buffer.concat([updated, tag, final], updated.byteLength + tag.byteLength + final.byteLength)
    return encrypted
  },

  chaCha20Poly1305Decrypt (ciphertext, nonce, ad, k, _dst) {
    const authTag = ciphertext.subarray(ciphertext.length - 16)
    const text = ciphertext.subarray(0, ciphertext.length - 16)
    const decipher = crypto.createDecipheriv(CHACHA_POLY1305, k, nonce, {
      authTagLength: 16
    })
    decipher.setAAD(ad, {
      plaintextLength: text.byteLength
    })
    decipher.setAuthTag(authTag)
    const updated = decipher.update(text)
    const final = decipher.final()
    if (final.byteLength > 0) {
      return Buffer.concat([updated, final], updated.byteLength + final.byteLength)
    }
    return updated
  }
}

const asCrypto: Pick<ICryptoInterface, 'hashSHA256' | 'chaCha20Poly1305Encrypt' | 'chaCha20Poly1305Decrypt'> = {
  hashSHA256 (data) {
    return digest(data)
  },
  chaCha20Poly1305Encrypt (plaintext, nonce, ad, k) {
    return asImpl.seal(k, nonce, plaintext, ad)
  },
  chaCha20Poly1305Decrypt (ciphertext, nonce, ad, k, dst) {
    return asImpl.open(k, nonce, ciphertext, ad, dst)
  }
}

// benchmarks show that for chacha20poly1305
// the as implementation is faster for smaller payloads(<1200)
// and the node implementation is faster for larger payloads
export const defaultCrypto: ICryptoInterface = {
  ...pureJsCrypto,
  hashSHA256 (data) {
    return nodeCrypto.hashSHA256(data)
  },
  chaCha20Poly1305Encrypt (plaintext, nonce, ad, k) {
    if (plaintext.length < 1200) {
      return asCrypto.chaCha20Poly1305Encrypt(plaintext, nonce, ad, k)
    }
    return nodeCrypto.chaCha20Poly1305Encrypt(plaintext, nonce, ad, k)
  },
  chaCha20Poly1305Decrypt (ciphertext, nonce, ad, k, dst) {
    if (ciphertext.length < 1200) {
      return asCrypto.chaCha20Poly1305Decrypt(ciphertext, nonce, ad, k, dst)
    }
    return nodeCrypto.chaCha20Poly1305Decrypt(ciphertext, nonce, ad, k, dst)
  },
  generateX25519KeyPair (): KeyPair {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519', {
      publicKeyEncoding: {
        type: 'spki',
        format: 'der'
      },
      privateKeyEncoding: {
        type: 'pkcs8',
        format: 'der'
      }
    })

    return {
      publicKey: publicKey.subarray(12),
      privateKey: privateKey.subarray(16)
    }
  },
  generateX25519KeyPairFromSeed (seed: Uint8Array): KeyPair {
    const privateKey = crypto.createPrivateKey({
      key: Buffer.concat([
        Buffer.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]),
        seed
      ]),
      type: 'pkcs8',
      format: 'der'
    })

    const publicKey = crypto.createPublicKey({
      // @ts-expect-errort types are wrong
      key: privateKey,
      type: 'spki',
      format: 'der'
    }).export({
      type: 'spki',
      format: 'der'
    }).subarray(12)

    return {
      publicKey,
      privateKey: seed
    }
  },
  generateX25519SharedKey (privateKey: Uint8Array, publicKey: Uint8Array): Uint8Array {
    publicKey = uint8ArrayConcat([
      Buffer.from([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00]),
      publicKey
    ])

    privateKey = uint8ArrayConcat([
      Buffer.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]),
      privateKey
    ])

    return crypto.diffieHellman({
      publicKey: crypto.createPublicKey({
        key: Buffer.from(publicKey, publicKey.byteOffset, publicKey.byteLength),
        type: 'spki',
        format: 'der'
      }),
      privateKey: crypto.createPrivateKey({
        key: Buffer.from(privateKey, privateKey.byteOffset, privateKey.byteLength),
        type: 'pkcs8',
        format: 'der'
      })
    })
  }
}

// no chacha20-poly1305 in electron https://github.com/electron/electron/issues/24024
if (isElectronMain) {
  defaultCrypto.chaCha20Poly1305Encrypt = asCrypto.chaCha20Poly1305Encrypt
  defaultCrypto.chaCha20Poly1305Decrypt = asCrypto.chaCha20Poly1305Decrypt
}
