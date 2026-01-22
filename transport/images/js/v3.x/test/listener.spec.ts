/* eslint-disable no-console */
/* eslint-env mocha */

import { multiaddr } from '@multiformats/multiaddr'
import { getLibp2p } from './fixtures/get-libp2p.js'
import { redisProxy } from './fixtures/redis-proxy.js'
import type { Libp2p } from '@libp2p/interface'
import type { Ping } from '@libp2p/ping'
import type { Multiaddr } from '@multiformats/multiaddr'

// Test framework sets uppercase env vars (IS_DIALER, TEST_KEY, TRANSPORT)
const isDialer: boolean = process.env.IS_DIALER === 'true'
// Framework timeout: use TEST_TIMEOUT_SECS if set, otherwise default to 180 seconds
const timeoutMs: number = parseInt(process.env.TEST_TIMEOUT_SECS ?? '180') * 1000

describe('ping test (listener)', function () {
  if (isDialer) {
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

  it('should listen for ping', async function () {
    this.timeout(timeoutMs + 30_000)

    const sortByNonLocalIp = (a: Multiaddr, b: Multiaddr): -1 | 0 | 1 => {
      if (a.toString().includes('127.0.0.1')) {
        return 1
      }

      return -1
    }

    let multiaddrs = node.getMultiaddrs().sort(sortByNonLocalIp).map(ma => ma.toString())

    const transport = process.env.TRANSPORT
    if (!transport) {
      throw new Error('TRANSPORT environment variable is required')
    }
    if (transport === 'webrtc') {
      const relayAddr = process.env.RELAY_ADDR
      const hasWebrtcMultiaddr = new Promise<string[]>((resolve) => {
        const abortController = new AbortController()
        node.addEventListener('self:peer:update', (event) => {
          const webrtcMas = node.getMultiaddrs().filter(ma => ma.toString().includes('/webrtc'))
          if (webrtcMas.length > 0) {
            resolve(webrtcMas.sort(sortByNonLocalIp).map(ma => ma.toString()))
          }
          abortController.abort()
        }, { signal: abortController.signal })
      })

      if (relayAddr == null || relayAddr === '') {
        throw new Error('No relayAddr')
      }
      // const conn = await node.dial(multiaddr(relayAddr))
      console.error('dial relay')
      await node.dial(multiaddr(relayAddr), {
        signal: AbortSignal.timeout(timeoutMs)
      })
      console.error('wait for relay reservation')
      multiaddrs = await hasWebrtcMultiaddr
    }

    console.error('inform redis of dial address')
    console.error(multiaddrs)
    // Use TEST_KEY for Redis key namespacing (required by transport test framework)
    const testKey = process.env.TEST_KEY
    if (!testKey) {
      throw new Error('TEST_KEY environment variable is required')
    }
    const redisKey: string = `${testKey}_listener_multiaddr`
    // Send the listener addr over the proxy server so this works on both the Browser and Node
    // Redis Coordination Protocol:
    // - Key format: {TEST_KEY}_listener_multiaddr (per transport test framework spec)
    // - Operation: RPUSH (Redis list operation) - creates a list with the multiaddr
    // - Why RPUSH/BLPOP: Blocking list operations allow dialer to wait efficiently
    //   without polling. This matches Rust/Python implementations for compatibility.
    // - Key cleanup: Delete key first to prevent WRONGTYPE errors from leftover
    //   data (string vs list type conflicts) from previous test runs
    try {
      await redisProxy(['DEL', redisKey])
    } catch (err) {
      // Ignore if key doesn't exist or other non-critical errors
      // This is safe because we're about to create the key with RPUSH
    }
    // Publish listener address using RPUSH (list operation)
    // Dialer will use BLPOP to block and read this value
    await redisProxy(['RPUSH', redisKey, multiaddrs[0]])
    // Wait
    console.error('wait for incoming ping')
    await new Promise(resolve => setTimeout(resolve, timeoutMs))
  })
})
