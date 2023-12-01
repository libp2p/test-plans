import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { tcp } from '@libp2p/tcp'
import { multiaddr } from '@multiformats/multiaddr'
import { createLibp2p } from 'libp2p'
import { perf } from '@libp2p/perf'
import { parseArgs } from 'node:util'

const argv = parseArgs({
  options: {
    'run-server': {
      type: 'string',
      default: 'false'
    },
    'server-address': {
      type: 'string'
    },
    transport: {
      type: 'string',
      default: 'tcp'
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
 * @param {string} serverIpAddress
 * @param {string} transport
 * @param {number} uploadBytes
 * @param {number} downloadBytes
 */
export async function main (runServer, serverIpAddress, transport, uploadBytes, downloadBytes) {
  const { host, port } = splitHostPort(serverIpAddress)

  const config = {
    transports: [
      tcp()
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
      perf: perf()
    }
  }

  if (runServer) {
    Object.assign(config, {
      addresses: {
        listen: [
          // #TODO: right now we only support tcp
          `/ip4/${host}/tcp/${port}`
        ]
      }
    })
  }

  const node = await createLibp2p(config)

  await node.start()

  if (!runServer) {
    for await (const output of node.services.perf.measurePerformance(multiaddr(`/ip4/${host}/tcp/${port}`), uploadBytes, downloadBytes)) {
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

main(argv.values['run-server'] === 'true', argv.values['server-address'], argv.values.transport, Number(argv.values['upload-bytes']), Number(argv.values['download-bytes'])).catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err)
  process.exit(1)
})
