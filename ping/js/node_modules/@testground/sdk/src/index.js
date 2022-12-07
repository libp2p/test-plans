'use strict'

const runtime = require('./runtime')
const sync = require('./sync')
const network = require('./network')
const env = require('./env')

const { registerTestcaseResult } = require('./env/env')

/** @typedef {import('./runtime').RunEnv} RunEnv */
/** @typedef {import('./sync').SyncClient} SyncClient */

/**
 * Takes a map of test case names and their functions, and calls the matched
 * test case, or throws an error if the name is unrecognized.
 *
 * @param {Record<string, function(RunEnv):Promise<void>>} cases
 */
async function invokeMap (cases) {
  const runenv = runtime.currentRunEnv()

  if (cases[runenv.testCase]) {
    try {
      await invokeHelper(runenv, cases[runenv.testCase])
    } catch (err) {
      registerAndMessageTestcaseResult(err, runenv)
      throw err
    }
  } else {
    const err = new Error(`unrecognized test case: ${runenv.testCase}`)
    registerAndMessageTestcaseResult(err, runenv)
    throw err
  }
}

/**
 * @param {unknown} result
 * @param {RunEnv} runenv
 */
function registerAndMessageTestcaseResult (result, runenv) {
  runenv.recordMessage(`registerTestcaseResult: ${result}`)
  registerTestcaseResult(result)
}

/**
 * Runs the passed test-case and reports the result.
 *
 * @param {function(RunEnv):Promise<void>} fn
 */
async function invoke (fn) {
  const runenv = runtime.currentRunEnv()
  await invokeHelper(runenv, fn)
}

/**
 * @param {RunEnv} runenv
 * @param {function(RunEnv, SyncClient?):Promise<void>} fn
 */
async function invokeHelper (runenv, fn) {
  let client = /** @type {SyncClient|null} */ (null)

  if (fn.length >= 2) {
    client = await sync.newBoundClient(runenv)
    runenv.setSignalEmitter(client)
  }

  await runenv.recordStart()

  let /** @type {unknown} */ testResult = true
  try {
    await fn(runenv, client)
    await runenv.recordSuccess()
  } catch (err) {
    await runenv.recordFailure(err)
    testResult = err
  } finally {
    if (client) {
      client.close()
    }
    registerAndMessageTestcaseResult(testResult, runenv)
  }
}

module.exports = {
  invoke,
  invokeMap,

  env,
  network,
  runtime,
  sync
}
