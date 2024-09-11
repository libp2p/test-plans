import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { circuitRelayServer } from '@libp2p/circuit-relay-v2'
import { identify } from '@libp2p/identify'
import { webSockets } from '@libp2p/websockets'
import { createLibp2p } from 'libp2p'

const {
  LISTEN_PORT,
  EXTERNAL_IP
} = process.env

const node = await createLibp2p({
  addresses: {
    listen: [
      `/ip4/0.0.0.0/tcp/${LISTEN_PORT}/ws`
    ],
    announce: [
      `/ip4/${EXTERNAL_IP}/tcp/${LISTEN_PORT}/ws`
    ]
  },
  transports: [
    webSockets()
  ],
  streamMuxers: [
    yamux()
  ],
  connectionEncryption: [
    noise()
  ],
  connectionManager: {
    minConnections: 0
  },
  services: {
    identify: identify(),
    relay: circuitRelayServer({
      reservations: {
        maxReservations: 1024 * 1024
      }
    })
  }
})

console.info(node.getMultiaddrs()[0].toString())
