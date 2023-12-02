import { Uint8ArrayList } from 'uint8arraylist'
import { alloc as uint8ArrayAlloc, allocUnsafe as uint8ArrayAllocUnsafe } from 'uint8arrays/alloc'
import type { bytes } from './@types/basic.js'
import type { MessageBuffer } from './@types/handshake.js'
import type { LengthDecoderFunction } from 'it-length-prefixed'

export const uint16BEEncode = (value: number): Uint8Array => {
  const target = uint8ArrayAllocUnsafe(2)
  new DataView(target.buffer, target.byteOffset, target.byteLength).setUint16(0, value, false)
  return target
}
uint16BEEncode.bytes = 2

export const uint16BEDecode: LengthDecoderFunction = (data: Uint8Array | Uint8ArrayList): number => {
  if (data.length < 2) throw RangeError('Could not decode int16BE')

  if (data instanceof Uint8Array) {
    return new DataView(data.buffer, data.byteOffset, data.byteLength).getUint16(0, false)
  }

  return data.getUint16(0)
}
uint16BEDecode.bytes = 2

// Note: IK and XX encoder usage is opposite (XX uses in stages encode0 where IK uses encode1)

export function encode0 (message: MessageBuffer): Uint8ArrayList {
  return new Uint8ArrayList(message.ne, message.ciphertext)
}

export function encode1 (message: MessageBuffer): Uint8ArrayList {
  return new Uint8ArrayList(message.ne, message.ns, message.ciphertext)
}

export function encode2 (message: MessageBuffer): Uint8ArrayList {
  return new Uint8ArrayList(message.ns, message.ciphertext)
}

export function decode0 (input: bytes): MessageBuffer {
  if (input.length < 32) {
    throw new Error('Cannot decode stage 0 MessageBuffer: length less than 32 bytes.')
  }

  return {
    ne: input.subarray(0, 32),
    ciphertext: input.subarray(32, input.length),
    ns: uint8ArrayAlloc(0)
  }
}

export function decode1 (input: bytes): MessageBuffer {
  if (input.length < 80) {
    throw new Error('Cannot decode stage 1 MessageBuffer: length less than 80 bytes.')
  }

  return {
    ne: input.subarray(0, 32),
    ns: input.subarray(32, 80),
    ciphertext: input.subarray(80, input.length)
  }
}

export function decode2 (input: bytes): MessageBuffer {
  if (input.length < 48) {
    throw new Error('Cannot decode stage 2 MessageBuffer: length less than 48 bytes.')
  }

  return {
    ne: uint8ArrayAlloc(0),
    ns: input.subarray(0, 48),
    ciphertext: input.subarray(48, input.length)
  }
}
