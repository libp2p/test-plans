import { parseArgs } from 'node:util'
import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { perf } from '@libp2p/perf'
import { tls } from '@libp2p/tls'
import { tcp } from '@libp2p/tcp'
import { webRTCDirect } from '@libp2p/webrtc'
import { webSockets } from '@libp2p/websockets'
import { multiaddr, fromStringTuples } from '@multiformats/multiaddr'
import { createLibp2p } from 'libp2p'

const argv = parseArgs({
  options: {
    'run-server': {
      type: 'string',
      default: 'false'
    },
    'server-address': {
      type: 'string'
    },
    'server-multiaddr': {
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
 * @param {string} serverPublicSocketAddress
 * @param {string} serverMultiaddr
 * @param {string} transport
 * @param {string} encryption
 * @param {number} uploadBytes
 * @param {number} downloadBytes
 */
export async function main (runServer, serverPublicSocketAddress, serverMultiaddr, transport, encryption, uploadBytes, downloadBytes) {
  const { host, port } = splitHostPort(serverPublicSocketAddress)

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
  }

  if (runServer) {
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
    }
  }

  const node = await createLibp2p(config)

  await node.start()

  if (runServer) {
    // print our multiaddr (may have certhashes in it)
    console.error(node.getMultiaddrs()[0].toString())
  } else {
    // replace server host/port with values from public address
    const privateMa = multiaddr(serverMultiaddr)
    const tuples = privateMa.stringTuples()

    for (let i = 0; i < tuples.length; i++) {
      // ipv4
      if (tuples[i][0] === 4) {
        tuples[i][1] = host
      }

      // udp
      if (tuples[i][0] === 6 || tuples[i][0] === 273) {
        tuples[i][1] = port
      }
    }

    const serverMa = fromStringTuples(tuples)

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

main(argv.values['run-server'] === 'true', argv.values['server-address'], argv.values['server-multiaddr'], argv.values.transport, argv.values.encryption, Number(argv.values['upload-bytes']), Number(argv.values['download-bytes'])).catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err)
  process.exit(1)
})
