/* eslint-disable no-console */
/* eslint-env mocha */

import { } from 'aegir/chai'
import { createLibp2p, Libp2pOptions } from 'libp2p'
import { webTransport } from '@libp2p/webtransport'
import { tcp } from '@libp2p/tcp'
import { webSockets } from '@libp2p/websockets'
import { noise } from '@chainsafe/libp2p-noise'
import { mplex } from '@libp2p/mplex'
import { yamux } from '@chainsafe/libp2p-yamux'
import { multiaddr } from '@multiformats/multiaddr'

async function redisProxy(commands: any[]): Promise<any> {
  const res = await fetch(`http://localhost:${process.env.proxyPort}/`, { body: JSON.stringify(commands), method: "POST" })
  if (!res.ok) {
    throw new Error("Redis command failed")
  }
  return await res.json()
}

describe('ping test', () => {
  it('should ping', async () => {
    const TRANSPORT = process.env.transport
    const SECURE_CHANNEL = process.env.security
    const MUXER = process.env.muxer
    const isDialer = process.env.is_dialer === "true"
    const IP = process.env.ip
    const options: Libp2pOptions = {
      start: true
    }

    switch (TRANSPORT) {
      case 'tcp':
        options.transports = [tcp()]
        options.addresses = {
          listen: isDialer ? [] : [`/ip4/${IP}/tcp/0`]
        }
        break
      case 'webtransport':
        options.transports = [webTransport()]
        if (!isDialer) {
          throw new Error("WebTransport is not supported as a listener")
        }
        break
      case 'ws':
        options.transports = [webSockets()]
        options.addresses = {
          listen: isDialer ? [] : [`/ip4/${IP}/tcp/0/ws`]
        }
        break
      default:
        throw new Error(`Unknown transport: ${TRANSPORT}`)
    }

    switch (SECURE_CHANNEL) {
      case 'noise':
        options.connectionEncryption = [noise()]
        break
      case 'quic':
        options.connectionEncryption = [noise()]
        break
      default:
        throw new Error(`Unknown secure channel: ${SECURE_CHANNEL}`)
    }

    switch (MUXER) {
      case 'mplex':
        options.streamMuxers = [mplex()]
        break
      case 'yamux':
        options.streamMuxers = [yamux()]
        break
      case 'quic':
        break
      default:
        throw new Error(`Unknown muxer: ${MUXER}`)
    }

    const node = await createLibp2p(options)

    try {
      if (isDialer) {
        const otherMa = (await redisProxy(["BLPOP", "listenerAddr", "10"]).catch(err => { throw new Error("Failed to wait for listener") }))[1]
        console.log(`node ${node.peerId} pings: ${otherMa}`)
        const rtt = await node.ping(multiaddr(otherMa))
        console.log(`Ping successful: ${rtt}`)
        await redisProxy(["RPUSH", "dialerDone", ""])
      } else {
        const multiaddrs = node.getMultiaddrs().map(ma => ma.toString()).filter(maString => !maString.includes("127.0.0.1"))
        console.log("My multiaddrs are", multiaddrs)
        // Send the listener addr over the proxy server so this works on both the Browser and Node
        await redisProxy(["RPUSH", "listenerAddr", multiaddrs[0]])
        try {
          await redisProxy(["BLPOP", "dialerDone", "10"])
        } catch {
          throw new Error("Failed to wait for dialer to finish")
        }
      }
    } finally {
      // sleep for a second
      await new Promise(resolve => setTimeout(resolve, 1000))
      try {
        // We don't care if this fails
        await node.stop()
      } catch { }
    }
  })
})