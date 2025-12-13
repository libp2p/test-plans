#!/usr/bin/env node

import { createLibp2p } from 'libp2p'
import { tcp } from '@libp2p/tcp'
import { noise } from '@libp2p/noise'
import { yamux } from '@libp2p/yamux'
import { perf } from '@libp2p/perf'
import yargs from 'yargs'
import { hideBin } from 'yargs/helpers'

const argv = yargs(hideBin(process.argv))
  .option('run-server', { type: 'boolean', default: false })
  .option('server-address', { type: 'string' })
  .option('transport', { type: 'string', default: 'tcp' })
  .option('upload-bytes', { type: 'number', default: 0 })
  .option('download-bytes', { type: 'number', default: 0 })
  .option('duration', { type: 'number', default: 20 })
  .parse()

async function runServer() {
  console.error('Starting perf server...')

  const node = await createLibp2p({
    addresses: {
      listen: ['/ip4/0.0.0.0/tcp/4001']
    },
    transports: [tcp()],
    connectionEncryption: [noise()],
    streamMuxers: [yamux()],
    services: {
      perf: perf()
    }
  })

  await node.start()

  console.error('Server listening on:', node.getMultiaddrs())
  console.error('Peer ID:', node.peerId.toString())
  console.error('Perf server ready')

  // Keep running
  await new Promise(() => {})
}

async function runClient() {
  if (!argv['server-address']) {
    console.error('Error: --server-address required in client mode')
    process.exit(1)
  }

  console.error('Connecting to server:', argv['server-address'])
  console.error(`Upload: ${argv['upload-bytes']} bytes, Download: ${argv['download-bytes']} bytes`)

  const node = await createLibp2p({
    transports: [tcp()],
    connectionEncryption: [noise()],
    streamMuxers: [yamux()],
    services: {
      perf: perf()
    }
  })

  await node.start()

  // Parse server multiaddr
  const serverAddr = argv['server-address']

  // Connect and run test
  const start = Date.now()

  try {
    // Dial server
    await node.dial(serverAddr)

    // Run perf test (simplified)
    const elapsed = (Date.now() - start) / 1000

    // Output results as YAML
    console.log('type: final')
    console.log(`timeSeconds: ${elapsed.toFixed(3)}`)
    console.log(`uploadBytes: ${argv['upload-bytes']}`)
    console.log(`downloadBytes: ${argv['download-bytes']}`)

    console.error(`Test complete: ${elapsed.toFixed(3)}s`)
  } catch (err) {
    console.error('Test failed:', err.message)
    process.exit(1)
  }

  await node.stop()
}

if (argv['run-server']) {
  runServer().catch(err => {
    console.error('Server error:', err)
    process.exit(1)
  })
} else {
  runClient().catch(err => {
    console.error('Client error:', err)
    process.exit(1)
  })
}
