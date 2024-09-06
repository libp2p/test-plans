import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { createLibp2p } from 'libp2p'
import { perf } from '@libp2p/perf'
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { webRTC } from '@libp2p/webrtc'
import { tcp } from '@libp2p/tcp'
import { identify } from '@libp2p/identify'
import { multiaddr } from '@multiformats/multiaddr'
import { webSockets } from '@libp2p/websockets'
import { all } from '@libp2p/websockets/filters'

const transport = process.env.TRANSPORT
const listenerAddress = process.env.LISTENER_ADDRESS
const uploadBytes = Number(process.env.UPLOAD_BYTES)
const downloadBytes = Number(process.env.DOWNLOAD_BYTES)

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
  }
}

if (transport === 'tcp') {
  config.transports.push(tcp())
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

for await (const output of node.services.perf.measurePerformance(multiaddr(listenerAddress), uploadBytes, downloadBytes)) {
  // eslint-disable-next-line no-console
  console.log(JSON.stringify(output))
}

process.exit(0)
