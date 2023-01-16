import { spawn, exec } from "child_process";
import { existsSync } from "fs";
import { createClient } from 'redis'
import http from "http"

const isDialer = process.env.is_dialer === "true"
const REDIS_ADDR = process.env.REDIS_ADDR || 'redis:6379'

// Used to preinstall the browsers in the docker image
const initialSetup = process.env.initial_setup === "true"

/** @type {import('aegir/types').PartialOptions} */
export default {
  test: {
    async before() {
      if (initialSetup) {
        return {}
      }

      const redisClient = createClient({
        url: `redis://${REDIS_ADDR}`
      })
      redisClient.on('error', (err) => console.error(`Redis Client Error: ${err}`))
      await redisClient.connect()

      const requestListener = async function (req, res) {
        const requestJSON = await new Promise(resolve => {
          let body = ""
          req.on('data', function (data) {
            body += data;
          });

          req.on('end', function () {
            resolve(JSON.parse(body))
          });
        })

        try {

          if (requestJSON.listenerAddr) {
            await redisClient.rPush('listenerAddr', requestJSON.listenerAddr)
          }

          if (requestJSON.popDialerDone) {
            const res = await redisClient.blPop('dialerDone', 10)
            if (res === null) {
              throw new Error("timeout waiting for dialer done")
            }
          }
        } catch (err) {
          console.error(err)
          res.writeHead(500, {
            'Access-Control-Allow-Origin': '*'
          })
          res.end(err.toString())
          return
        }


        res.writeHead(200, {
          'Access-Control-Allow-Origin': '*'
        })
        res.end()
      };

      const proxyServer = http.createServer(requestListener);
      await new Promise(resolve => { proxyServer.listen(0, "localhost", () => { resolve() }); })

      let otherMa = null;
      if (isDialer) {
        otherMa = (await redisClient.blPop('listenerAddr', 10))?.element
      }

      return {
        redisClient,
        proxyServer: proxyServer,
        env: {
          ...process.env,
          otherMa,
          proxyPort: proxyServer.address().port
        }
      }
    },
    async after(_, { proxyServer, redisClient }) {
      if (initialSetup) {
        return
      }

      await new Promise(resolve => {
        proxyServer.close(() => resolve());
      })

      if (isDialer) {
        await redisClient.rPush('dialerDone', '')
      }
      try {
        // We don't care if this fails
        await redisClient.disconnect()
      } catch { }
    }
  },
  build: {
    bundlesizeMax: '18kB'
  }
}