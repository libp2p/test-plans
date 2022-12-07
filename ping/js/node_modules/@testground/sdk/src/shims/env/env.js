'use strict'

/**
 * Gets the environment that can be used by the environment
 * to create the runtime.
 *
 * @returns {Record<string, string|undefined>}
 */
function getProcessEnv () {
  // @ts-ignore
  return (window.testground || {}).env
}
/**
 * @param {unknown} result
 */
function registerTestcaseResult (result) {
  // @ts-ignore
  if (!window.testground) {
    // @ts-ignore
    window.testground = {}
  }
  // @ts-ignore
  window.testground.result = result
}

module.exports = {
  getProcessEnv,
  registerTestcaseResult
}
