#!/usr/bin/env node

/**
 * JS-libp2p Echo Server for interoperability tests
 * Implements the Echo protocol (/echo/1.0.0) and publishes multiaddr to Redis
 */

import { createLibp2p } from 'libp2p'
import { tcp } from '@libp2p/tcp'
import { noise } from '@libp2p/noise'
import { yamux } from '@libp2p/yamux'
import { mplex } from '@libp2p/mplex'
import { identify } from '@libp2p/identify'
import { ping } from '@libp2p/ping'
import { pipe } from 'it-pipe'
import { createClient } from 'redis'

// Echo protocol ID
const ECHO_PROTOCOL = '/echo/1.0.0'

// Environment configuration
const config = {
  transport: process.env.TRANSPORT || 'tcp',
  security: process.env.SECURITY || 'noise', 
  muxer: process.env.MUXER || 'yamux',
  redisAddr: process.env.REDIS_ADDR || 'redis://localhost:6379',
  port: parseInt(process.env.PORT || '0', 10),
  host: process.env.HOST || '0.0.0.0'
}

/**
 * Echo protocol handler - pipes the stream back to the source
 */
async function handleEchoProtocol({ stream }) {
  try {
    await pipe(stream.source, stream.sink)
  } catch (error) {
    console.error(`Echo protocol error: ${error.message}`)
    throw error
  }
}

/**
 * Create libp2p node with configured protocols
 */
async function createNode() {
  const transports = []
  if (config.transport === 'tcp') {
    transports.push(tcp())
  }
  
  const connectionEncryption = []
  if (config.security === 'noise') {
    connectionEncryption.push(noise())
  }
  
  const streamMuxers = []
  if (config.muxer === 'yamux') {
    streamMuxers.push(yamux())
  } else if (config.muxer === 'mplex') {
    streamMuxers.push(mplex())
  }
  
  const node = await createLibp2p({
    addresses: {
      listen: [`/ip4/${config.host}/tcp/${config.port}`]
    },
    transports,
    connectionEncryption,
    streamMuxers,
    services: {
      identify: identify(),
      ping: ping()
    }
  })
  
  await node.handle(ECHO_PROTOCOL, handleEchoProtocol)
  return node
}

/**
 * Publish multiaddr to Redis for coordination
 */
async function publishMultiaddr(multiaddr) {
  let redisClient = null
  
  try {
    redisClient = createClient({ url: config.redisAddr })
    await redisClient.connect()
    
    const key = 'js-echo-server-multiaddr'
    await redisClient.rPush(key, multiaddr)
    await redisClient.expire(key, 300)
    
  } catch (error) {
    console.error(`Redis error: ${error.message}`)
  } finally {
    if (redisClient) {
      try {
        await redisClient.quit()
      } catch (error) {
        console.error(`Redis cleanup error: ${error.message}`)
      }
    }
  }
}

/**
 * Main server function
 */
async function main() {
  try {
    const node = await createNode()
    await node.start()
    
    const multiaddrs = node.getMultiaddrs()
    if (multiaddrs.length === 0) {
      throw new Error('No listening addresses found')
    }
    
    const multiaddr = multiaddrs[0].toString()
    console.log(multiaddr) // Output to stdout for test coordination
    
    await publishMultiaddr(multiaddr)
    
    // Graceful shutdown
    const handleShutdown = async (signal) => {
      console.error(`Received ${signal}, shutting down...`)
      await node.stop()
      process.exit(0)
    }
    
    process.on('SIGINT', () => handleShutdown('SIGINT'))
    process.on('SIGTERM', () => handleShutdown('SIGTERM'))
    
    // Keep running
    await new Promise(() => {})
    
  } catch (error) {
    console.error(`Server error: ${error.message}`)
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(`Fatal error: ${error.message}`)
  process.exit(1)
})