import { invokeMap } from '@testground/sdk'

const testcases = {
  ping: require('./ping')
}

;(async () => {
  // This is the plan entry point.
  await invokeMap(testcases)
})()
