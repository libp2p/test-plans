import os from 'os'
import path from 'path'
import { existsSync } from 'fs'
import fs from 'fs/promises'
import crypto from 'crypto'

import webpack from 'webpack'

// bundles the test file using webpack to a temporary directory,
// ready to be served by your automated browser for testing purposes
export async function bundle (testFile) {
  const contextDir = process.cwd()

  console.log(`bundle test file: ${testFile} (context: ${contextDir})`)

  const tmpdir = path.join(os.tmpdir(), 'testground')
  if (!(existsSync(tmpdir))) {
    await fs.mkdir(tmpdir)
  }
  const bundleFileName = `${hashFileName(testFile)}.${randomId()}.test.bundle.js`

  return await new Promise((resolve, reject) => {
    webpack({
      context: contextDir,
      entry: testFile,
      target: 'web',
      output: {
        path: tmpdir,
        filename: bundleFileName
      },
      mode: 'development',
      devtool: false
    }, (err, stats) => {
      if (err || stats.hasErrors()) {
        if (err) {
          console.error(err.stack || err)
          if (err.details) {
            console.error(err.details)
          }
          reject(err)
          return
        }
      }

      resolve(path.join(tmpdir, bundleFileName))
    })
  })
}

function hashFileName (name) {
  return crypto.createHash('sha256').update(name).digest('hex')
}

function randomId () {
  return crypto.randomBytes(8).toString('hex')
}
