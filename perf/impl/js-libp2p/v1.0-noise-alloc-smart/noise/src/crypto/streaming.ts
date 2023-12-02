import { Uint8ArrayList } from 'uint8arraylist'
import { allocUnsafe as uint8ArrayAllocUnsafe } from 'uint8arrays/alloc'
import { NOISE_MSG_MAX_LENGTH_BYTES, NOISE_MSG_MAX_LENGTH_BYTES_WITHOUT_TAG } from '../constants.js'
import { uint16BEEncode } from '../encoder.js'
import type { IHandshake } from '../@types/handshake-interface.js'
import type { MetricsRegistry } from '../metrics.js'
import type { Transform } from 'it-stream-types'

const CHACHA_TAG_LENGTH = 16

// Returns generator that encrypts payload from the user
export function encryptStream (handshake: IHandshake, metrics?: MetricsRegistry): Transform<AsyncGenerator<Uint8Array | Uint8ArrayList>> {
  return async function * (source) {
    for await (const chunk of source) {
      for (let i = 0; i < chunk.length; i += NOISE_MSG_MAX_LENGTH_BYTES_WITHOUT_TAG) {
        let end = i + NOISE_MSG_MAX_LENGTH_BYTES_WITHOUT_TAG
        if (end > chunk.length) {
          end = chunk.length
        }

        let data: Uint8Array | Uint8ArrayList

        if (chunk instanceof Uint8Array) {
          data = handshake.encrypt(chunk.subarray(i, end), handshake.session)
        } else {
          data = handshake.encrypt(chunk.sublist(i, end), handshake.session)
        }

        metrics?.encryptedPackets.increment()

        yield new Uint8ArrayList(uint16BEEncode(data.byteLength), data)
      }
    }
  }
}

// Decrypt received payload to the user
export function decryptStream (handshake: IHandshake, metrics?: MetricsRegistry): Transform<AsyncGenerator<Uint8ArrayList>, AsyncGenerator<Uint8Array | Uint8ArrayList>> {
  return async function * (source) {
    for await (const chunk of source) {
      for (let i = 0; i < chunk.length; i += NOISE_MSG_MAX_LENGTH_BYTES) {
        let end = i + NOISE_MSG_MAX_LENGTH_BYTES
        if (end > chunk.length) {
          end = chunk.length
        }

        if (end - CHACHA_TAG_LENGTH < i) {
          throw new Error('Invalid chunk')
        }

        const encrypted = chunk.sublist(i, end)

        let dst: Uint8Array

        // @ts-expect-error .bufs is private
        if (encrypted.bufs.length === 1) {
          dst = chunk.subarray(i, end - CHACHA_TAG_LENGTH)
        } else {
          dst = uint8ArrayAllocUnsafe(end - CHACHA_TAG_LENGTH - i)
        }

        const { plaintext: decrypted, valid } = handshake.decrypt(encrypted, handshake.session, dst)
        if (!valid) {
          metrics?.decryptErrors.increment()
          throw new Error('Failed to validate decrypted chunk')
        }
        metrics?.decryptedPackets.increment()
        yield decrypted
      }
    }
  }
}
