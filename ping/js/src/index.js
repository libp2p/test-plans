import pkg from '@testground/sdk'
const { invokeMap } = pkg

import ping from './ping.js'

const testcases = {
  ping
}

;(async () => {
  // This is the plan entry point.
  await invokeMap(testcases)
})()
