'use strict'

/**
 * Gets the environment that can be used by the environment
 * to create the runtime.
 *
 * @returns {Record<string, string|undefined>}
 */
function getProcessEnv () {
  return process.env
}

/**
 * @param {unknown} _result
 */
function registerTestcaseResult (_result) {
  // function is used in the browser shim
  // to gain the ability to wait until invokeMap is finished
}

module.exports = {
  getProcessEnv,
  registerTestcaseResult
}
