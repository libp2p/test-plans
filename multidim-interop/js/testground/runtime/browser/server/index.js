import path from 'path'
import { fileURLToPath } from 'url'

import express from 'express'
import mustacheExpress from 'mustache-express'

import { redis } from '../../redis.js'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

/**
 * Exposes a minimal express server
 * on the desired port, serving the static folder as is.
 *
 * Only goal of this server is to serve the test together
 * with the dependencies in the selected browser environment.
 */
export default async (port, bundledTestFilePath) => {
  const app = express()

  const assetsDir = path.dirname(bundledTestFilePath)
  const testBundleFile = path.basename(bundledTestFilePath)

  // serve the bundled file as a static file
  app.use(express.static(assetsDir))

  // support json parsing of request body automatically
  app.use(express.json())

  // render our index.html as a template,
  // as to be able to inject the bundled test file (name)
  app.engine('mustache', mustacheExpress())
  app.set('view engine', 'mustache')
  app.set('views', path.join(__dirname, 'templates'))
  app.get('/', (_req, res) => {
    res.render('index', { testBundleFile })
  })

  // support the redis-over-http proxy,
  // as to allow the wo-testground plan to use redis as if it is actually available,
  // what can possibly go wrong?
  const redisClient = await redis(process.env.REDIS_ADDR)
  app.on('exit', async () => {
    await redisClient.disconnect()
  })
  app.post('/runtime/redis', async (req, res) => {
    try {
        const { method, args } = req.body
        console.log(`redis http proxy received method call ${method} with args: ${args}`)
        const output = await redisClient[method](...args)
        console.log(`redis http proxy: sending back output: ${output}`)
        res.json({ output })
    } catch (error) {
        console.log(`redis http proxy: sending back error: ${error}`)
        res.json({ error })
    }
  })

  return new Promise((resolve) => {
    app.listen(port, () => {
      console.log(`local web server running on port ${port}`)
      resolve()
    })
  })
}
