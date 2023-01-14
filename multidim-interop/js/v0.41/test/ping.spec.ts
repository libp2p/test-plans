/* eslint-disable no-console */
/* eslint-env mocha */

import { } from 'aegir/chai'
// import { createClient } from 'redis'

import { createLibp2p, Libp2pOptions } from 'libp2p'
// import { tcp } from '@libp2p/tcp'
import { webSockets } from '@libp2p/websockets'
import { noise } from '@chainsafe/libp2p-noise'
import { mplex } from '@libp2p/mplex'
import { yamux } from '@chainsafe/libp2p-yamux'
import { multiaddr } from '@multiformats/multiaddr'

describe('ping test', () => {
  it('should ping', async () => {
    let nodeFetchImport = "node-fetch"
    let fetch = (typeof window === "undefined") ?
      (await import(nodeFetchImport)).default :
      window.fetch

    const TRANSPORT = process.env.transport
    const SECURE_CHANNEL = process.env.security
    const MUXER = process.env.muxer
    const IS_DIALER_STR = process.env.is_dialer
    const IP = process.env.ip

    const isDialer = IS_DIALER_STR === 'true'
    const options: Libp2pOptions = {
      start: true
    }

    switch (TRANSPORT) {
      case 'tcp':
        // Dynamic so this doesn't get imported in the browser
        const tcpImport = "@libp2p/tcp"
        const { tcp } = await import(tcpImport)
        options.transports = [tcp()]
        options.addresses = {
          listen: [`/ip4/${IP}/tcp/0`]
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
      default:
        throw new Error(`Unknown secure channel: ${TRANSPORT}`)
    }

    switch (MUXER) {
      case 'mplex':
        options.streamMuxers = [mplex()]
        break
      case 'yamux':
        options.streamMuxers = [yamux()]
        break
      default:
        throw new Error(`Unknown muxer: ${MUXER}`)
    }

    const node = await createLibp2p(options)

    try {

      if (isDialer) {
        const otherMa = process.env.otherMa
        if (otherMa === undefined) {
          throw new Error("Failed to wait for listener")
        }
        console.log(`node ${node.peerId} pings: ${otherMa}`)
        const rtt = await node.ping(multiaddr(otherMa))
        console.log(`Ping successful: ${rtt}`)
      } else {
        const multiaddrs = node.getMultiaddrs().map(ma => ma.toString()).filter(maString => !maString.includes("127.0.0.1"))
        console.log("My multiaddrs are", multiaddrs)
        // Send the listener addr over the proxy server so this works on both the Browser and Node
        await fetch(`http://localhost:${process.env.proxyPort}/`, { body: JSON.stringify({ "listenerAddr": multiaddrs[0] }), method: "POST" })
        const res = await fetch(`http://localhost:${process.env.proxyPort}/`, { body: JSON.stringify({ "popDialerDone": true }), method: "POST" })
        if (!res.ok) {
          throw new Error("Failed to wait for dialer to finish")
        }
      }
    } finally {
      try {
        // We don't care if this fails
        await node.stop()
      } catch { }
    }
  })
})