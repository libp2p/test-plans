/* eslint-disable no-console */
/* eslint-env mocha */

import { multiaddr } from '@multiformats/multiaddr'
import { getLibp2p } from './fixtures/get-libp2p.js'
import { redisProxy } from './fixtures/redis-proxy.js'
import type { Libp2p } from '@libp2p/interface'
import type { Ping } from '@libp2p/ping'

// Test framework sets uppercase env vars (IS_DIALER, TEST_KEY)
// but also check lowercase for compatibility
const isDialer: boolean = process.env.IS_DIALER === 'true' || process.env.is_dialer === 'true'
const timeoutMs: number = parseInt(process.env.test_timeout_secs ?? '180') * 1000
// Use TEST_KEY for Redis key namespacing (required by transport test framework)
const testKey: string = process.env.TEST_KEY ?? process.env.test_key ?? ''
if (!testKey) {
  throw new Error('TEST_KEY environment variable is required')
}
const redisKey: string = `${testKey}_listener_multiaddr`

describe('ping test (dialer)', function () {
  if (!isDialer) {
    return
  }

  // make the default timeout longer than the listener timeout
  this.timeout(timeoutMs + 30_000)
  let node: Libp2p<{ ping: Ping }>

  beforeEach(async () => {
    node = await getLibp2p()
  })

  afterEach(async () => {
    // Shutdown libp2p node
    try {
      // We don't care if this fails
      await node.stop()
    } catch { }
  })

  it('should dial and ping', async function () {
    this.timeout(timeoutMs + 30_000)

    // Redis Coordination Protocol:
    // - Key format: {TEST_KEY}_listener_multiaddr (per transport test framework spec)
    // - Operation: BLPOP (blocking list pop) - waits for listener address
    // - Why BLPOP: Blocking operation avoids polling, matches Rust/Python
    // - Return value: BLPOP returns [key, value] array where value is the multiaddr string
    // - Timeout: BLPOP will block until data is available or timeout is reached
    // Note: Redis commands must be strings, so convert timeout to string
    const redisWaitTimeout = Math.min(timeoutMs / 1000, 180) // Convert to seconds, max 180s
    const timeoutSeconds = Math.max(1, Math.floor(redisWaitTimeout)).toString()
    const blpopResult = await redisProxy(['BLPOP', redisKey, timeoutSeconds])
    
    let otherMaStr: string | null = null
    if (blpopResult && Array.isArray(blpopResult) && blpopResult.length > 1) {
      // BLPOP returns [key, value] - extract the multiaddr string (value)
      otherMaStr = blpopResult[1] as string
    }
    
    if (!otherMaStr) {
      throw new Error(`Timeout waiting for listener address from Redis key: ${redisKey} after ${redisWaitTimeout}s`)
    }

    // Hack until these are merged:
    // - https://github.com/multiformats/js-multiaddr-to-uri/pull/120
    otherMaStr = otherMaStr.replace('/tls/ws', '/wss')

    const otherMa = multiaddr(otherMaStr)
    const handshakeStartInstant = Date.now()

    console.error(`node ${node.peerId.toString()} dials: ${otherMa}`)
    await node.dial(otherMa, {
      signal: AbortSignal.timeout(timeoutMs)
    })

    console.error(`node ${node.peerId.toString()} pings: ${otherMa}`)
    const pingRTT = await node.services.ping.ping(multiaddr(otherMa), {
      signal: AbortSignal.timeout(timeoutMs)
    })
    const handshakePlusOneRTT = Date.now() - handshakeStartInstant
    // Output YAML format as specified in transport test framework
    console.log('latency:')
    console.log(`  handshake_plus_one_rtt: ${handshakePlusOneRTT}`)
    console.log(`  ping_rtt: ${pingRTT}`)
    console.log('  unit: ms')
  })
})
