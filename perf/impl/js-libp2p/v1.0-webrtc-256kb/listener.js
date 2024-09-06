import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { createLibp2p } from 'libp2p'
import { perf } from '@libp2p/perf'
import { WebRTC, TCP } from '@multiformats/multiaddr-matcher'
import { webSockets } from '@libp2p/websockets'
import { all } from '@libp2p/websockets/filters'
import { identify } from '@libp2p/identify'
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { webRTC } from '@libp2p/webrtc'
import { tcp } from '@libp2p/tcp'

const transport = process.env.TRANSPORT
const relayAddress = process.env.RELAY_ADDRESS
const listenPort = process.env.LISTEN_PORT
const externalIp = process.env.EXTERNAL_IP

const config = {
  transports: [],
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
    perf: perf(),
    identify: identify()
  },
  connectionGater: {
    denyDialMultiaddr: () => false
  }
}

if (transport === 'tcp') {
  config.transports.push(tcp())

  config.addresses = {
    listen: [
      `/ip4/0.0.0.0/tcp/${listenPort}`
    ],
    announce: [
      `/ip4/${externalIp}/tcp/${listenPort}`
    ]
  }
} else if (transport === 'webrtc') {
  config.transports.push(circuitRelayTransport())
  config.transports.push(webRTC({
    dataChannel: {
      maxMessageSize: 256 * 1024
    }
  }))
  config.transports.push(webSockets({
    filter: all
  }))

  config.addresses = {
    listen: [
      `${relayAddress}/p2p-circuit`,
      '/webrtc'
    ],
    announce: [
      `${relayAddress}/p2p-circuit/webrtc`,
    ]
  }
} else if (transport === 'ws') {
  config.transports.push(webSockets({
    filter: all
  }))
} else if (transport === 'wss') {
  config.transports.push(webSockets({
    filter: all
  }))
}

const node = await createLibp2p(config)
let multiaddr

if (transport === 'tcp') {
  multiaddr = node.getMultiaddrs()
    .filter(ma => TCP.matches(ma))
    .map(ma => ma.toString())
    .pop()
} else if (transport === 'webrtc') {
  multiaddr = node.getMultiaddrs()
    .filter(ma => WebRTC.matches(ma))
    .map(ma => ma.toString())
    .pop()
}

// only need to print out one multiaddr because the runner will switch the
// private IP for the public one before passing it to the client/server
console.info(multiaddr)
