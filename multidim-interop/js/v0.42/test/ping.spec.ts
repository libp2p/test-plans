/* eslint-disable no-console */
/* eslint-env mocha */

import { } from 'aegir/chai'
import { createLibp2p, Libp2pOptions } from 'libp2p'
import { webTransport } from '@libp2p/webtransport'
import { tcp } from '@libp2p/tcp'
import { webSockets } from '@libp2p/websockets'
import * as filters from "@libp2p/websockets/filters"
import { noise } from '@chainsafe/libp2p-noise'
import { mplex } from '@libp2p/mplex'
import { yamux } from '@chainsafe/libp2p-yamux'
import { multiaddr } from '@multiformats/multiaddr'
import { webRTC, webRTCDirect } from '@libp2p/webrtc'

async function redisProxy(commands: any[]): Promise<any> {
  const res = await fetch(`http://localhost:${process.env.proxyPort}/`, { body: JSON.stringify(commands), method: "POST" })
  if (!res.ok) {
    throw new Error("Redis command failed")
  }
  return await res.json()
}

const CIRCUIT_RELAY_CODE = 290

describe('ping test', () => {
  it('should ping', async () => {
    const TRANSPORT = process.env.transport
    const SECURE_CHANNEL = process.env.security
    const MUXER = process.env.muxer
    const isDialer = process.env.is_dialer === "true"
    const relayAddr = process.env.relay_addr ?? ""
    const IP = process.env.ip || "0.0.0.0"
    const timeoutSecs: string = process.env.test_timeout_secs || "180"

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
      case 'webrtc':
        options.transports = [webRTC()]
        options.addresses = {
          listen: isDialer ? [] : [`/ip4/${IP}/udp/0/webrtc`]
        }
        break
      case 'webrtc-private-to-private':
        options.transports = [
          webSockets({
            filter: filters.all,
          }),
          webRTCDirect({}),
        ]
        options.relay = {
          enabled: true,
          autoRelay: {
            enabled: true,
          },
        }
        break
      case 'ws':
        options.transports = [webSockets()]
        options.addresses = {
          listen: isDialer ? [] : [`/ip4/${IP}/tcp/0/ws`]
        }
        break
      case 'wss':
        process.env["NODE_TLS_REJECT_UNAUTHORIZED"] = "0"
        options.transports = [webSockets()]
        options.addresses = {
          listen: isDialer ? [] : [`/ip4/${IP}/tcp/0/wss`]
        }
        break
      default:
        throw new Error(`Unknown transport: ${TRANSPORT}`)
    }

    let skipSecureChannel = false
    let skipMuxer = false
    switch (TRANSPORT) {
      case 'webtransport':
      case 'webrtc':
        skipSecureChannel = true
        skipMuxer = true
    }

    if (!skipSecureChannel) {
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
    } else {
      // Libp2p requires at least one encryption module. Even if unused.
      options.connectionEncryption = [noise()]
    }

    if (!skipMuxer) {
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
    }

    const node = await createLibp2p(options)

    try {
      if (isDialer) {
        var otherMa = (await redisProxy(["BLPOP", "listenerAddr", timeoutSecs]).catch(err => { throw new Error("Failed to wait for listener") }))[1]
        // Hack until these are merged:
        // - https://github.com/multiformats/js-multiaddr/pull/312 
        // - https://github.com/multiformats/js-multiaddr-to-uri/pull/120
        otherMa = otherMa.replace("/tls/ws", "/wss")

        console.error(`node ${node.peerId} pings: ${otherMa}`)
        const handshakeStartInstant = Date.now()
        await node.dial(multiaddr(otherMa))
        const pingRTT = await node.ping(multiaddr(otherMa))
        const handshakePlusOneRTT = Date.now() - handshakeStartInstant
        console.log(JSON.stringify({
          handshakePlusOneRTTMillis: handshakePlusOneRTT,
          pingRTTMilllis: pingRTT
        }))
      } else {
        let multiaddrs = node.getMultiaddrs().map(ma => ma.toString()).filter(maString => !maString.includes("127.0.0.1"))

        if (TRANSPORT === "webrtc-private-to-private") {
          // Connect to relay node
          await node.dial(multiaddr(relayAddr))

          // wait for the relay to be ready
          multiaddrs = [await new Promise((resolve) => {
            node.peerStore.addEventListener("change:multiaddrs", (event) => {
              const { peerId } = event.detail

              if (node.getMultiaddrs().length === 0 || !node.peerId.equals(peerId)) {
                return
              }

              for (const ma of node.getMultiaddrs()) {
                if (ma.protoCodes().includes(CIRCUIT_RELAY_CODE)) {
                  const newWebrtcDirectAddress = multiaddr(ma.encapsulate(
                    multiaddr(`/webrtc-w3c/p2p/${node.peerId}`)
                  ))
                  resolve(newWebrtcDirectAddress.toString())
                  return
                }
              }
            })
          })]
        }

        if (multiaddrs.length === 0) {
          throw new Error("No multiaddrs found")
        }
        console.error("My multiaddrs are", multiaddrs)
        // Send the listener addr over the proxy server so this works on both the Browser and Node
        await redisProxy(["RPUSH", "listenerAddr", multiaddrs[0]])
        // Wait
        await new Promise(resolve => setTimeout(resolve, 1000 * parseInt(timeoutSecs, 10)))
      }
    } catch (err) {
      // Show all errors in an aggregated error
      if (err instanceof AggregateError) {
        console.error(`unexpected exception in ping test: ${err}\n Errors:`, err.errors)
      } else {
        console.error(`unexpected exception in ping test:`, err)
      }
      throw err
    } finally {
      try {
        // We don't care if this fails
        await node.stop()
      } catch { }
    }
  })
})