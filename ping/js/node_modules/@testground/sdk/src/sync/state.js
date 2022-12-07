'use strict'

/** @typedef {import('../runtime').RunParams} RunParams */
/** @typedef {import('./types').State} State */
/** @typedef {import('./types').Response} Response */
/** @typedef {import('./types').Request} Request */
/** @typedef {import('./types').Socket} Socket */
/** @typedef {import('./types').PubSub} PubSub */
/** @typedef {import('events').EventEmitter} EventEmitter */

/**
 * @param {string} state
 * @param {RunParams} params
 * @returns {string}
 */
function stateKey (state, params) {
  return `run:${params.testRun}:plan:${params.testPlan}:case:${params.testCase}:states:${state}`
}

/**
 * @param {RunParams} params
 * @returns {string}
 */
function eventsKey (params) {
  return `run:${params.testRun}:plan:${params.testPlan}:case:${params.testCase}:run_events`
}

/**
 * @param {import('winston').Logger} logger
 * @param {function():Promise<RunParams>} extractor
 * @param {PubSub} pubsub
 * @param {Socket} socket
 * @returns {State}
 */
function createState (logger, extractor, pubsub, socket) {
  return {
    barrier: async (state, target) => {
      // a barrier with target zero is satisfied immediately; log a warning as
      // this is probably programmer error.
      if (target === 0) {
        logger.warn('requested a barrier with target zero; satisfying immediately', { state })
        return {
          cancel: () => {},
          wait: Promise.resolve()
        }
      }

      const params = await extractor()
      if (!params) {
        throw new Error('no run parameters provided')
      }

      const key = stateKey(state, params)

      const res = socket.request({
        barrier: {
          state: key,
          target
        }
      })

      const wait = (async () => {
        // Waits till next (and single) reply.
        await res.wait.next()
        res.cancel()
      })()

      return {
        wait,
        cancel: res.cancel
      }
    },
    signalEntry: async (state) => {
      const params = await extractor()
      if (!params) {
        throw new Error('no run parameters provided')
      }

      const key = stateKey(state, params)
      logger.debug('signalling entry to state', { key })

      const res = await socket.requestOnce({
        signal_entry: {
          state: key
        }
      })

      if (res.error) {
        throw new Error(res.error)
      }

      logger.debug('new value of state', { key, value: res.signal_entry.seq })
      return res.signal_entry.seq
    },

    signalEvent: async (event) => {
      const params = await extractor()
      if (!params) {
        throw new Error('no run parameters provided')
      }

      const key = eventsKey(params)
      logger.debug('signalling event', { key, value: event })
      await pubsub.publish(key, event)
      logger.debug('successfully signalled event', { key })
    }
  }
}

module.exports = {
  createState
}
