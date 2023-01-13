#!/usr/bin/env node

import { fork } from 'child_process'

; (async () => {
    const RUNTIME = process.env.TESTGROUND_RUNTIME || 'node' // other possibilities: chromium, webkit, firefox

    const testFile = process.argv[2]

    if (RUNTIME === 'node') {
        fork(testFile)
    } else if (['chromium', 'webkit', 'firefox'].indexOf(RUNTIME) > -1) {
        throw new Error(`Unsupported browser runtime: ${RUNTIME}`)
    } else {
        throw new Error(`Unsupported runtime: ${RUNTIME}`)
    }
})()