#!/usr/bin/env node

import { fork } from 'child_process'

import yargs from 'yargs/yargs'
import { hideBin } from 'yargs/helpers'

; (async () => {
    const argv = yargs(hideBin(process.argv))
        .command('<path>', 'path to the test file to run')
        .demandCommand(1)
        .parseSync()

    const RUNTIME = argv.runtime || 'node' // other possibilities: chromium, webkit, firefox

    const testFile = argv._[0]

    if (RUNTIME === 'node') {
        fork(testFile)
    } else if (['chromium', 'webkit', 'firefox'].indexOf(RUNTIME) > -1) {
        // 1. webpack the test file
        // TODO

        // 2. run the test using the browser runtime
    } else {
        throw new Error(`Unsupported runtime: ${RUNTIME}`)
    }
})()