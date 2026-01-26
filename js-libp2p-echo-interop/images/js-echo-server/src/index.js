#!/usr/bin/env node

/**
 * JS-libp2p Echo Server for interoperability tests
 * 
 * This server implements the Echo protocol (/echo/1.0.0) and publishes its
 * multiaddr to Redis for coordination with test clients.
 */

// Polyfill for Promise.withResolvers (Node.js < 22)
if (typeof Promise.withResolvers === 'undefined') {
  Promise.withResolvers = function() {
    let resolve, reject
    const promise = new Promise((res, rej) => {
      resolve = res
      reject = rej
    })
    return { promise, resolve, reject }
  }
}

import { createLibp2p } from 'libp2p'
import { tcp } from '@libp2p/tcp'
import { noise } from '@libp2p/noise'
import { yamux } from '@libp2p/yamux'
// Note: mplex is deprecated but still included for interoperability testing
// with py-libp2p implementations that may still use mplex
import { mplex } from '@libp2p/mplex'
import { identify } from '@libp2p/identify'
import { ping } from '@libp2p/ping'
import { pipe } from 'it-pipe'
import { createClient } from 'redis'
import { validateConfigurationOrExit } from './config-validator.js'

// Echo protocol ID
const ECHO_PROTOCOL = '/echo/1.0.0'

// Environment configuration
const config = {
  transport: process.env.TRANSPORT || 'tcp',
  security: process.env.SECURITY || 'noise', 
  muxer: process.env.MUXER || 'yamux',
  isDialer: process.env.IS_DIALER === 'true',
  redisAddr: process.env.REDIS_ADDR || 'redis://localhost:6379',
  port: parseInt(process.env.PORT || '0', 10), // 0 for random port
  host: process.env.HOST || '0.0.0.0'
}

/**
 * Echo protocol handler - pipes the stream back to the source
 * @param {Object} params - Handler parameters
 * @param {Stream} params.stream - The libp2p stream
 * @param {Connection} params.connection - The libp2p connection
 */
async function handleEchoProtocol({ stream, connection }) {
  try {
    console.error(`[DEBUG] Echo protocol handler started for peer: ${connection.remotePeer}`)
    
    // Pipe the stream back to itself (echo functionality)
    await pipe(
      stream.source,
      stream.sink
    )
    
    console.error(`[DEBUG] Echo protocol handler completed for peer: ${connection.remotePeer}`)
  } catch (error) {
    console.error(`[ERROR] Echo protocol handler error: ${error.message}`)
    throw error
  }
}

/**
 * Create libp2p node with configured transport, security, and muxer
 */
async function createNode() {
  // Configure transports
  const transports = []
  if (config.transport === 'tcp') {
    transports.push(tcp())
  }
  // Add other transports as needed (QUIC, WebSocket, etc.)
  
  // Configure security protocols
  const connectionEncryption = []
  if (config.security === 'noise') {
    connectionEncryption.push(noise())
  }
  // Add TLS support as needed
  
  // Configure stream multiplexers
  const streamMuxers = []
  if (config.muxer === 'yamux') {
    streamMuxers.push(yamux())
  } else if (config.muxer === 'mplex') {
    // Note: mplex is deprecated but still supported for interoperability testing
    // with legacy py-libp2p implementations. Yamux is preferred for new deployments.
    streamMuxers.push(mplex())
  }
  
  // Create libp2p node
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
  
  // Register Echo protocol handler
  await node.handle(ECHO_PROTOCOL, handleEchoProtocol)
  
  return node
}

/**
 * Publish multiaddr to Redis for coordination
 */
async function publishMultiaddr(multiaddr) {
  let redisClient = null
  
  try {
    console.error(`[DEBUG] Connecting to Redis at: ${config.redisAddr}`)
    redisClient = createClient({ url: config.redisAddr })
    
    redisClient.on('error', (err) => {
      console.error(`[ERROR] Redis client error: ${err.message}`)
    })
    
    await redisClient.connect()
    console.error(`[DEBUG] Connected to Redis successfully`)
    
    // Publish multiaddr to Redis list
    const key = 'js-echo-server-multiaddr'
    await redisClient.rPush(key, multiaddr)
    console.error(`[DEBUG] Published multiaddr to Redis key '${key}': ${multiaddr}`)
    
    // Set expiration for cleanup (5 minutes)
    await redisClient.expire(key, 300)
    
  } catch (error) {
    console.error(`[ERROR] Failed to publish multiaddr to Redis: ${error.message}`)
    // Don't fail the server if Redis is unavailable
  } finally {
    if (redisClient) {
      try {
        await redisClient.quit()
      } catch (error) {
        console.error(`[ERROR] Error closing Redis connection: ${error.message}`)
      }
    }
  }
}

/**
 * Health check endpoint for container lifecycle management
 */
function setupHealthCheck() {
  // Simple health check that can be called by Docker health checks
  process.on('message', (msg) => {
    if (msg === 'health-check') {
      process.send('healthy')
    }
  })
}

/**
 * Enhanced ready state detection
 */
async function waitForReadyState(node) {
  const maxRetries = 30
  const retryDelay = 1000 // 1 second
  
  for (let i = 0; i < maxRetries; i++) {
    try {
      // Check if node is started and has listening addresses
      if (node.status === 'started' && node.getMultiaddrs().length > 0) {
        console.error(`[INFO] Node ready state achieved after ${i + 1} attempts`)
        return true
      }
      
      console.error(`[DEBUG] Waiting for ready state... attempt ${i + 1}/${maxRetries}`)
      await new Promise(resolve => setTimeout(resolve, retryDelay))
    } catch (error) {
      console.error(`[DEBUG] Ready state check error: ${error.message}`)
    }
  }
  
  throw new Error('Failed to achieve ready state within timeout')
}

/**
 * Enhanced startup sequence with better error handling
 */
async function startupSequence() {
  console.error(`[INFO] Starting JS-libp2p Echo Server startup sequence`)
  
  // Phase 1: Configuration validation
  console.error(`[INFO] Phase 1: Configuration validation`)
  validateConfigurationOrExit(config)
  
  console.error(`[INFO]   Transport: ${config.transport}`)
  console.error(`[INFO]   Security: ${config.security}`)
  console.error(`[INFO]   Muxer: ${config.muxer}`)
  console.error(`[INFO]   Is Dialer: ${config.isDialer}`)
  console.error(`[INFO]   Redis Address: ${config.redisAddr}`)
  console.error(`[INFO]   Listen Address: ${config.host}:${config.port}`)
  
  // Phase 2: Node creation and startup
  console.error(`[INFO] Phase 2: Creating and starting libp2p node`)
  const node = await createNode()
  await node.start()
  
  console.error(`[INFO] libp2p node started with peer ID: ${node.peerId}`)
  
  // Phase 3: Ready state detection
  console.error(`[INFO] Phase 3: Waiting for ready state`)
  await waitForReadyState(node)
  
  // Phase 4: Address binding and publication
  console.error(`[INFO] Phase 4: Address binding and publication`)
  const multiaddrs = node.getMultiaddrs()
  if (multiaddrs.length === 0) {
    throw new Error('No listening addresses found after startup')
  }
  
  const multiaddr = multiaddrs[0].toString()
  console.error(`[INFO] Listening on: ${multiaddr}`)
  
  // Output multiaddr to stdout for test coordination (this signals readiness)
  console.log(multiaddr)
  
  // Phase 5: Redis coordination
  console.error(`[INFO] Phase 5: Publishing multiaddr to Redis`)
  await publishMultiaddr(multiaddr)
  
  console.error(`[INFO] Echo Server startup sequence completed successfully`)
  console.error(`[INFO] Echo protocol: ${ECHO_PROTOCOL}`)
  console.error(`[INFO] Server is ready and waiting for connections`)
  
  return node
}

/**
 * Enhanced shutdown sequence with proper resource cleanup
 */
async function shutdownSequence(node, signal) {
  console.error(`[INFO] Starting shutdown sequence (signal: ${signal})`)
  
  let exitCode = 0
  
  try {
    // Phase 1: Stop accepting new connections
    console.error(`[INFO] Phase 1: Stopping new connections`)
    // libp2p doesn't have a direct way to stop accepting connections
    // but stopping the node will handle this
    
    // Phase 2: Close existing connections gracefully
    console.error(`[INFO] Phase 2: Closing existing connections`)
    const connections = node.getConnections()
    console.error(`[INFO] Closing ${connections.length} active connections`)
    
    for (const connection of connections) {
      try {
        await connection.close()
        console.error(`[DEBUG] Closed connection to ${connection.remotePeer}`)
      } catch (error) {
        console.error(`[WARN] Error closing connection to ${connection.remotePeer}: ${error.message}`)
      }
    }
    
    // Phase 3: Stop libp2p node
    console.error(`[INFO] Phase 3: Stopping libp2p node`)
    await node.stop()
    console.error(`[INFO] libp2p node stopped successfully`)
    
    // Phase 4: Cleanup Redis resources (optional)
    console.error(`[INFO] Phase 4: Cleanup completed`)
    
  } catch (error) {
    console.error(`[ERROR] Error during shutdown: ${error.message}`)
    exitCode = 1
  }
  
  console.error(`[INFO] Shutdown sequence completed (exit code: ${exitCode})`)
  process.exit(exitCode)
}

/**
 * Main server function with enhanced lifecycle management
 */
async function main() {
  let node = null
  
  try {
    // Setup health check
    setupHealthCheck()
    
    // Execute startup sequence
    node = await startupSequence()
    
    // Setup graceful shutdown handlers
    const handleShutdown = (signal) => {
      console.error(`[INFO] Received ${signal}, initiating graceful shutdown...`)
      shutdownSequence(node, signal).catch((error) => {
        console.error(`[FATAL] Shutdown sequence failed: ${error.message}`)
        process.exit(1)
      })
    }
    
    process.on('SIGINT', () => handleShutdown('SIGINT'))
    process.on('SIGTERM', () => handleShutdown('SIGTERM'))
    process.on('SIGQUIT', () => handleShutdown('SIGQUIT'))
    
    // Setup periodic health reporting
    const healthInterval = setInterval(() => {
      const connections = node.getConnections()
      const multiaddrs = node.getMultiaddrs()
      console.error(`[HEALTH] Status: ${node.status}, Connections: ${connections.length}, Addresses: ${multiaddrs.length}`)
    }, 30000) // Every 30 seconds
    
    // Cleanup interval on shutdown
    process.on('exit', () => {
      clearInterval(healthInterval)
    })
    
    // Keep the process running
    await new Promise(() => {}) // Never resolves
    
  } catch (error) {
    console.error(`[ERROR] Failed to start Echo Server: ${error.message}`)
    console.error(error.stack)
    
    // Attempt cleanup if node was created
    if (node) {
      try {
        await node.stop()
      } catch (cleanupError) {
        console.error(`[ERROR] Error during cleanup: ${cleanupError.message}`)
      }
    }
    
    process.exit(1)
  }
}

// Start the server
main().catch((error) => {
  console.error(`[FATAL] Unhandled error: ${error.message}`)
  console.error(error.stack)
  process.exit(1)
})