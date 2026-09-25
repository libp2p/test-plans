#!/usr/bin/env node

/**
 * Simple JS-libp2p Echo Server for interoperability tests
 */

import { createLibp2p } from 'libp2p'
import { createClient } from 'redis'

// Echo protocol ID
const ECHO_PROTOCOL = '/echo/1.0.0'

// Environment configuration
const config = {
  redisAddr: process.env.REDIS_ADDR || 'redis://localhost:6379',
  port: parseInt(process.env.PORT || '0', 10),
  host: process.env.HOST || '0.0.0.0'
}

/**
 * Echo protocol handler - pipes the stream back to the source
 */
async function handleEchoProtocol({ stream }) {
  try {
    console.error('Handling echo protocol request')
    
    // Read data from stream
    const chunks = []
    for await (const chunk of stream.source) {
      chunks.push(chunk)
    }
    
    // Echo back the data
    const data = new Uint8Array(chunks.reduce((acc, chunk) => acc + chunk.length, 0))
    let offset = 0
    for (const chunk of chunks) {
      data.set(chunk, offset)
      offset += chunk.length
    }
    
    // Write back to stream
    await stream.sink([data])
    
    console.error(`Echoed ${data.length} bytes`)
  } catch (error) {
    console.error(`Echo protocol error: ${error.message}`)
  }
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
    
    console.error(`Published multiaddr to Redis: ${multiaddr}`)
    
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
    // Create libp2p node with default configuration
    const node = await createLibp2p({
      addresses: {
        listen: [`/ip4/${config.host}/tcp/${config.port}`]
      }
    })
    
    // Handle echo protocol
    await node.handle(ECHO_PROTOCOL, handleEchoProtocol)
    
    // Start the node
    await node.start()
    
    const multiaddrs = node.getMultiaddrs()
    if (multiaddrs.length === 0) {
      throw new Error('No listening addresses found')
    }
    
    const multiaddr = multiaddrs[0].toString()
    console.log(multiaddr) // Output to stdout for test coordination
    
    await publishMultiaddr(multiaddr)
    
    console.error('Echo server started successfully')
    
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
    console.error(error.stack)
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(`Fatal error: ${error.message}`)
  console.error(error.stack)
  process.exit(1)
})