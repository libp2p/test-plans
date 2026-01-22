/* eslint-disable no-console */
import http from 'http'
import { pEvent } from 'p-event'
import { createClient } from 'redis'

// Test framework sets uppercase env vars (REDIS_ADDR, TRANSPORT, IS_DIALER)
// Note: These are validated in the before() hook, not at module load time,
// because .aegir.js is loaded during Docker build when env vars aren't set yet

/** @type {import('aegir/types').PartialOptions} */
export default {
  test: {
    browser: {
      config: {
        // Ignore self signed certificates
        browserContextOptions: { ignoreHTTPSErrors: true }
      }
    },
    async before () {
      // Validate required environment variables
      const redisAddr = process.env.REDIS_ADDR
      if (!redisAddr) {
        throw new Error('REDIS_ADDR environment variable is required')
      }
      const transport = process.env.TRANSPORT
      if (!transport) {
        throw new Error('TRANSPORT environment variable is required')
      }
      const isDialer = process.env.IS_DIALER === 'true'

      // import after build is complete
      const { createRelay } = await import('./dist/test/fixtures/relay.js')

      let relayNode
      let relayAddr
      if (transport === 'webrtc' && !isDialer) {
        relayNode = await createRelay()

        const sortByNonLocalIp = (a, b) => {
          if (a.toString().includes('127.0.0.1')) {
            return 1
          }
          return -1
        }

        relayAddr = relayNode.getMultiaddrs().sort(sortByNonLocalIp)[0].toString()
      }

      const redisClient = createClient({
        url: `redis://${redisAddr}`
      })
      redisClient.on('error', (err) => {
        console.error('Redis client error:', err)
      })
      await redisClient.connect()

      const requestListener = async function (req, res) {
        let requestJSON
        try {
          requestJSON = await new Promise((resolve, reject) => {
            let body = ''
            req.on('data', function (data) {
              body += data
            })

            req.on('end', function () {
              try {
                resolve(JSON.parse(body))
              } catch (parseErr) {
                reject(new Error(`Failed to parse request body: ${parseErr.message}`))
              }
            })
            req.on('error', function (err) {
              reject(new Error(`Request error: ${err.message}`))
            })
          })
        } catch (parseError) {
          console.error('Error parsing request:', parseError)
          res.writeHead(400, {
            'Access-Control-Allow-Origin': '*'
          })
          res.end(JSON.stringify({
            message: `Invalid request: ${parseError.message}`
          }))
          return
        }

        try {
          const redisRes = await redisClient.sendCommand(requestJSON)
          const command = requestJSON[0]?.toUpperCase()

          // For GET and BLPOP commands, null is a valid response:
          // - GET: null means key doesn't exist yet (expected when polling)
          // - BLPOP: null means timeout occurred (expected when listener hasn't published yet)
          // Both are valid responses and should be returned to the caller
          if (redisRes == null && command !== 'GET' && command !== 'BLPOP') {
            console.error('Redis failure - sent', requestJSON, 'received', redisRes)

            res.writeHead(500, {
              'Access-Control-Allow-Origin': '*'
            })
            res.end(JSON.stringify({
              message: 'Redis sent back null'
            }))

            return
          }

          res.writeHead(200, {
            'Access-Control-Allow-Origin': '*'
          })
          res.end(JSON.stringify(redisRes))
        } catch (err) {
          console.error('Error in redis command:', err)
          res.writeHead(500, {
            'Access-Control-Allow-Origin': '*'
          })
          res.end(err.toString())
        }
      }

      const proxyServer = http.createServer(requestListener)
      proxyServer.listen(0)

      await pEvent(proxyServer, 'listening', {
        signal: AbortSignal.timeout(5000)
      })

      return {
        redisClient,
        relayNode,
        proxyServer,
        env: {
          ...process.env,
          RELAY_ADDR: relayAddr,
          REDIS_PROXY_PORT: proxyServer.address().port
        }
      }
    },
    async after (_, { proxyServer, redisClient, relayNode }) {
      await new Promise(resolve => {
        proxyServer?.close(() => resolve())
      })

      try {
        // We don't care if this fails
        await redisClient?.disconnect()
        await relayNode?.stop()
      } catch { }
    }
  }
}
