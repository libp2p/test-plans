'use strict'

/** @typedef {import('../runtime').RunParams} RunParams */
/** @typedef {import('./types').PubSub} PubSub */
/** @typedef {import('./types').Response} Response */
/** @typedef {import('./types').Request} Request */
/** @typedef {import('./types').Socket} Socket */
/** @typedef {import('events').EventEmitter} EventEmitter */

/**
 * @param {import('winston').Logger} logger
 * @param {Socket} socket
 * @returns {PubSub}
 */
function createPubSub (logger, socket) {
  return {
    publish: async (topic, payload) => {
      const res = await socket.requestOnce({
        publish: {
          topic: topic,
          payload: payload
        }
      })

      if (res.error) {
        throw res.error
      }

      return res.publish.seq
    },
    subscribe: async (key) => {
      const { cancel, wait: waitSocket } = socket.request({
        subscribe: {
          topic: key
        }
      })

      const wait = (async function * () {
        for await (const res of waitSocket) {
          if (res.error) {
            throw new Error(res.error)
          }

          yield JSON.parse(res.subscribe)
        }
      })()

      return { cancel, wait }
    }
  }
}

module.exports = {
  createPubSub
}
