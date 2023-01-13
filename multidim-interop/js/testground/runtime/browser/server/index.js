import path from 'path'
import { fileURLToPath } from 'url'

import express from 'express'
import mustacheExpress from 'mustache-express'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

/**
 * Exposes a minimal express server
 * on the desired port, serving the static folder as is.
 *
 * Only goal of this server is to serve the test together
 * with the dependencies in the selected browser environment.
 */
export default (port, bundledTestFilePath) => {
  const app = express()

  const assetsDir = path.dirname(bundledTestFilePath)
  const testBundleFile = path.basename(bundledTestFilePath)

  // serve the bundled file as a static file
  app.use(express.static(assetsDir))

  // render our index.html as a template,
  // as to be able to inject the bundled test file (name)
  app.engine('mustache', mustacheExpress())
  app.set('view engine', 'mustache')
  app.set('views', path.join(__dirname, 'templates'))
  app.get('/', (_req, res) => {
    res.render('index', { testBundleFile })
  })

  return new Promise((resolve) => {
    app.listen(port, () => {
      console.log(`local web server running on port ${port}`)
      resolve()
    })
  })
}
