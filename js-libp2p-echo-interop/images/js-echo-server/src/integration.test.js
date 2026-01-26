/**
 * Integration test for JS Echo Server
 * Tests that the server can start and create a libp2p node
 */

import { test, describe } from 'node:test'
import assert from 'node:assert'
import { spawn } from 'node:child_process'

describe('JS Echo Server Integration', () => {
  test('should start server and output multiaddr', async () => {
    // Set a timeout for this test
    const timeout = 10000 // 10 seconds
    
    return new Promise((resolve, reject) => {
      const timeoutId = global.setTimeout(() => {
        server.kill('SIGTERM')
        reject(new Error('Test timeout: Server did not start within 10 seconds'))
      }, timeout)
      
      // Start the server process
      const server = spawn('node', ['src/index.js'], {
        cwd: process.cwd(),
        env: {
          ...process.env,
          TRANSPORT: 'tcp',
          SECURITY: 'noise',
          MUXER: 'yamux',
          IS_DIALER: 'false',
          REDIS_ADDR: 'redis://localhost:6379', // This will fail but that's ok for this test
          HOST: '127.0.0.1',
          PORT: '0'
        }
      })
      
      let stdoutData = ''
      let stderrData = ''
      
      server.stdout.on('data', (data) => {
        stdoutData += data.toString()
        
        // Check if we got a multiaddr (should start with /ip4/)
        if (stdoutData.includes('/ip4/')) {
          clearTimeout(timeoutId)
          server.kill('SIGTERM')
          
          // Validate the multiaddr format
          const lines = stdoutData.trim().split('\n')
          const multiaddr = lines[0]
          
          assert(multiaddr.startsWith('/ip4/'), 'Multiaddr should start with /ip4/')
          assert(multiaddr.includes('/tcp/'), 'Multiaddr should include /tcp/')
          assert(multiaddr.includes('/p2p/'), 'Multiaddr should include /p2p/')
          
          console.log('✓ Server started successfully and output multiaddr:', multiaddr)
          resolve()
        }
      })
      
      server.stderr.on('data', (data) => {
        stderrData += data.toString()
        
        // Check for fatal errors
        if (stderrData.includes('[FATAL]') || stderrData.includes('Failed to start Echo Server')) {
          clearTimeout(timeoutId)
          server.kill('SIGTERM')
          reject(new Error(`Server failed to start: ${stderrData}`))
        }
      })
      
      server.on('error', (error) => {
        clearTimeout(timeoutId)
        reject(new Error(`Failed to start server process: ${error.message}`))
      })
      
      server.on('exit', (code, signal) => {
        clearTimeout(timeoutId)
        if (code !== 0 && signal !== 'SIGTERM') {
          reject(new Error(`Server exited with code ${code}, stderr: ${stderrData}`))
        }
      })
    })
  })
})