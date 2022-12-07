'use strict'

const runtime = require('./runtime')
const sync = require('./sync')
const { getProcessEnv } = require('./env')

const ENV_TEST_PARAMETERS = [
  runtime.ENV_TEST_BRANCH,
  runtime.ENV_TEST_CASE,
  runtime.ENV_TEST_GROUP_ID,
  runtime.ENV_TEST_GROUP_INSTANCE_COUNT,
  runtime.ENV_TEST_INSTANCE_COUNT,
  runtime.ENV_TEST_INSTANCE_PARAMS,
  runtime.ENV_TEST_INSTANCE_ROLE,
  runtime.ENV_TEST_OUTPUTS_PATH,
  runtime.ENV_TEST_PLAN,
  runtime.ENV_TEST_REPO,
  runtime.ENV_TEST_RUN,
  runtime.ENV_TEST_SIDECAR,
  runtime.ENV_TEST_START_TIME,
  runtime.ENV_TEST_SUBNET,
  runtime.ENV_TEST_TAG,

  sync.ENV_SYNC_SERVICE_HOST,
  sync.ENV_SYNC_SERVICE_PORT
]

/**
 * Gets the parameters from the environment
 * that can be used by the environment to create the runtime.
 *
 * @returns {Record<string, string|undefined>}
 */
function getEnvParameters () {
  const env = getProcessEnv()
  return Object.keys(env)
    .filter(key => ENV_TEST_PARAMETERS.includes(key))
    .reduce((/** @type {Record<string, string|undefined>} */params, key) => {
      params[key] = env[key]
      return params
    }, {})
}

module.exports = {
  getEnvParameters
}
