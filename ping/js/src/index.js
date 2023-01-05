import pkg from '@testground/sdk'

import ping from './ping.js'
const { invokeMap } = pkg

const testcases = {
  ping
}

;(async () => {
  // This is the plan entry point.
  await invokeMap(testcases)
})()
