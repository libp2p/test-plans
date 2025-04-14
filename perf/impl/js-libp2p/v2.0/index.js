import { parseArgs } from 'node:util'
import { noise } from '@chainsafe/libp2p-noise'
import { quic } from '@chainsafe/libp2p-quic'
import { yamux } from '@chainsafe/libp2p-yamux'
import { perf } from '@libp2p/perf'
import { tls } from '@libp2p/tls'
import { tcp } from '@libp2p/tcp'
import { webRTCDirect } from '@libp2p/webrtc'
import { webSockets } from '@libp2p/websockets'
import { multiaddr } from '@multiformats/multiaddr'
import { createLibp2p } from 'libp2p'

const argv = parseArgs({
  options: {
    'run-server': {
      type: 'boolean',
      default: false
    },
    'server-address': {
      type: 'string'
    },
    transport: {
      type: 'string',
      default: 'tcp'
    },
    encryption: {
      type: 'string',
      default: 'noise'
    },
    'upload-bytes': {
      type: 'string',
      default: '0'
    },
    'download-bytes': {
      type: 'string',
      default: '0'
    }
  }
})

/**
 * @param {boolean} runServer
 * @param {string} serverAddress
 * @param {string} transport
 * @param {string} encryption
 * @param {number} uploadBytes
 * @param {number} downloadBytes
 */
export async function main (runServer, serverAddress, transport, encryption, uploadBytes, downloadBytes) {
  const config = {
    addresses: {},
    transports: [],
    streamMuxers: [
      yamux()
    ],
    connectionEncrypters: [],
    services: {
      perf: perf()
    }
  }

  if (encryption === 'tls') {
    config.connectionEncrypters.push(tls())
  } else if (encryption === 'noise') {
    config.connectionEncrypters.push(noise())
  }

  if (transport === 'tcp') {
    config.transports = [
      tcp()
    ]
  } else if (transport === 'webrtc-direct') {
    config.transports = [
      webRTCDirect()
    ]
  } else if (transport === 'ws') {
    config.transports = [
      webSockets()
    ]
  } else if (transport === 'quic-v1') {
    config.transports = [
      quic()
    ]
  }

  if (runServer) {
    const { host, port } = splitHostPort(serverAddress)

    if (transport === 'tcp') {
      config.addresses.listen = [
        `/ip4/${host}/tcp/${port}`
      ]
    } else if (transport === 'webrtc-direct') {
      config.addresses.listen = [
        `/ip4/${host}/udp/${port}/webrtc-direct`
      ]
    } else if (transport === 'ws') {
      config.addresses.listen = [
        `/ip4/${host}/tcp/${port}/ws`
      ]
    } else if (transport === 'quic-v1') {
      config.addresses.listen = [
        `/ip4/${host}/udp/${port}/quic-v1`
      ]
    }
  }

  const node = await createLibp2p(config)

  if (runServer) {
    // print our multiaddr (may have certhashes in it)
    for (const addr of node.getMultiaddrs()) {
      console.error(addr.toString())
    }
  } else {
    const serverMa = multiaddr(serverAddress)

    for await (const output of node.services.perf.measurePerformance(serverMa, uploadBytes, downloadBytes)) {
      // eslint-disable-next-line no-console
      console.log(JSON.stringify(output))
    }

    await node.stop()
  }
}

/**
 * @param {string} address
 * @returns { host: string, port?: string }
 */
function splitHostPort (address) {
  try {
    const parts = address.split(':')
    const host = parts[0]
    const port = parts[1]
    return {
      host,
      port
    }
  } catch (error) {
    throw Error('Invalid server address')
  }
}

main(argv.values['run-server'], argv.values['server-address'], argv.values.transport, argv.values.encryption, Number(argv.values['upload-bytes']), Number(argv.values['download-bytes'])).catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err)
  process.exit(1)
})
