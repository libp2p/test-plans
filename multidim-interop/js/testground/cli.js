#!/usr/bin/env node

import { fork } from 'child_process'

import yargs from 'yargs/yargs'
import { hideBin } from 'yargs/helpers'

import { bundle } from './cli/webpack.js'
import { run } from './runtime/browser/index.js'

; (async () => {
  const argv = yargs(hideBin(process.argv))
    .command('<path>', 'path to the test file to run')
    .demandCommand(1)
    .parseSync()

  const RUNTIME = argv.runtime || 'node' // other possibilities: chromium, webkit, firefox

  const testFile = argv._[0]

  if (RUNTIME === 'node') {
    // just run the test file in a forked node process, no preparation required
    fork(testFile)
  } else if (['chromium', 'webkit', 'firefox'].indexOf(RUNTIME) > -1) {
    // 1. webpack the test file
    const bundledTestFile = await bundle(testFile)
    console.log(bundledTestFile)

    // 2. run the test using the browser runtime
    await run(RUNTIME, bundledTestFile)
  } else {
    throw new Error(`Unsupported runtime: ${RUNTIME}`)
  }
})()
