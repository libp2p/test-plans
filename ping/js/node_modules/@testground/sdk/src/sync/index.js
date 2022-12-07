'use strict'

const { createSocket } = require('./socket')
const { createState } = require('./state')
const { createTopic } = require('./topic')
const { createSugar } = require('./sugar')
const { createPubSub } = require('./pubsub')

/** @typedef {import('winston').Logger} Logger */
/** @typedef {import('events').EventEmitter} EventEmitter */
/** @typedef {import('../runtime').RunEnv} RunEnv */
/** @typedef {import('../runtime').RunParams} RunParams */
/** @typedef {import('./types').SyncClient} SyncClient */
/** @typedef {import('./types').Request} Request */
/** @typedef {import('./types').Response} Response */

/**
 * Returns a new sync client that is bound to the provided runEnv. All the operations
 * will automatically be scoped to the keyspace of that run. You should call .close()
 * for a clean closure of the client.
 *
 * @param {RunEnv} runenv
 * @returns {Promise<SyncClient>}
 */
function newBoundClient (runenv) {
  return newClient(runenv.logger, () => Promise.resolve(runenv.runParams))
}

/**
 * @param {Logger} logger
 * @param {function():Promise<RunParams>} extractor
 * @returns {Promise<SyncClient>}
 */
async function newClient (logger, extractor) {
  const socket = await createSocket(logger)
  const pubsub = createPubSub(logger, socket)

  const base = {
    ...createState(logger, extractor, pubsub, socket),
    ...createTopic(logger, extractor, pubsub, socket)
  }

  return {
    ...base,
    ...createSugar(base),
    close: socket.close
  }
}

module.exports = {
  newBoundClient
}
