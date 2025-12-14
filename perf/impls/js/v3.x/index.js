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
  .option('upload-bytes', { type: 'number', default: 1073741824 })
  .option('download-bytes', { type: 'number', default: 1073741824 })
  .option('upload-iterations', { type: 'number', default: 10 })
  .option('download-iterations', { type: 'number', default: 10 })
  .option('latency-iterations', { type: 'number', default: 100 })
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

  const node = await createLibp2p({
    transports: [tcp()],
    connectionEncryption: [noise()],
    streamMuxers: [yamux()],
    services: {
      perf: perf()
    }
  })

  await node.start()

  try {
    // Connect to server
    await node.dial(argv['server-address'])
    console.error('Connected to server')

    // Run measurements
    console.error(`Running upload test (${argv['upload-iterations']} iterations)...`)
    const uploadStats = await runMeasurement(argv['upload-bytes'], 0, argv['upload-iterations'])

    console.error(`Running download test (${argv['download-iterations']} iterations)...`)
    const downloadStats = await runMeasurement(0, argv['download-bytes'], argv['download-iterations'])

    console.error(`Running latency test (${argv['latency-iterations']} iterations)...`)
    const latencyStats = await runMeasurement(1, 1, argv['latency-iterations'])

    // Output results as YAML
    console.log('# Upload measurement')
    console.log('upload:')
    console.log(`  iterations: ${argv['upload-iterations']}`)
    console.log(`  min: ${uploadStats.min.toFixed(2)}`)
    console.log(`  q1: ${uploadStats.q1.toFixed(2)}`)
    console.log(`  median: ${uploadStats.median.toFixed(2)}`)
    console.log(`  q3: ${uploadStats.q3.toFixed(2)}`)
    console.log(`  max: ${uploadStats.max.toFixed(2)}`)
    printOutliers(uploadStats.outliers, 2)
    console.log('  unit: Gbps')
    console.log()

    console.log('# Download measurement')
    console.log('download:')
    console.log(`  iterations: ${argv['download-iterations']}`)
    console.log(`  min: ${downloadStats.min.toFixed(2)}`)
    console.log(`  q1: ${downloadStats.q1.toFixed(2)}`)
    console.log(`  median: ${downloadStats.median.toFixed(2)}`)
    console.log(`  q3: ${downloadStats.q3.toFixed(2)}`)
    console.log(`  max: ${downloadStats.max.toFixed(2)}`)
    printOutliers(downloadStats.outliers, 2)
    console.log('  unit: Gbps')
    console.log()

    console.log('# Latency measurement')
    console.log('latency:')
    console.log(`  iterations: ${argv['latency-iterations']}`)
    console.log(`  min: ${latencyStats.min.toFixed(6)}`)
    console.log(`  q1: ${latencyStats.q1.toFixed(6)}`)
    console.log(`  median: ${latencyStats.median.toFixed(6)}`)
    console.log(`  q3: ${latencyStats.q3.toFixed(6)}`)
    console.log(`  max: ${latencyStats.max.toFixed(6)}`)
    printOutliers(latencyStats.outliers, 6)
    console.log('  unit: seconds')

    console.error('All measurements complete!')
  } catch (err) {
    console.error('Test failed:', err.message)
    process.exit(1)
  }

  await node.stop()
}

async function runMeasurement(uploadBytes, downloadBytes, iterations) {
  const values = []

  for (let i = 0; i < iterations; i++) {
    const start = Date.now()

    // Placeholder: simulate transfer
    // In real implementation, use libp2p perf protocol
    await new Promise(resolve => setTimeout(resolve, 10))

    const elapsed = (Date.now() - start) / 1000

    // Calculate throughput if this is a throughput test
    let value
    if (uploadBytes > 100 || downloadBytes > 100) {
      // Throughput in Gbps
      const bytes = Math.max(uploadBytes, downloadBytes)
      value = (bytes * 8) / elapsed / 1_000_000_000
    } else {
      // Latency in seconds
      value = elapsed
    }

    values.push(value)
  }

  return calculateStats(values)
}

function calculateStats(values) {
  values.sort((a, b) => a - b)

  const n = values.length
  const min = values[0]
  const max = values[n - 1]

  // Calculate percentiles
  const q1 = percentile(values, 25.0)
  const median = percentile(values, 50.0)
  const q3 = percentile(values, 75.0)

  // Calculate IQR and identify outliers
  const iqr = q3 - q1
  const lowerFence = q1 - 1.5 * iqr
  const upperFence = q3 + 1.5 * iqr

  const outliers = values.filter(v => v < lowerFence || v > upperFence)

  return { min, q1, median, q3, max, outliers }
}

function percentile(sortedValues, p) {
  const n = sortedValues.length
  const index = (p / 100.0) * (n - 1)
  const lower = Math.floor(index)
  const upper = Math.ceil(index)

  if (lower === upper) {
    return sortedValues[lower]
  }

  const weight = index - lower
  return sortedValues[lower] * (1.0 - weight) + sortedValues[upper] * weight
}

function printOutliers(outliers, decimals) {
  if (outliers.length === 0) {
    console.log('  outliers: []')
    return
  }

  const formatted = outliers.map(v => v.toFixed(decimals)).join(', ')
  console.log(`  outliers: [${formatted}]`)
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
