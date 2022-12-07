'use strict'

/** @typedef {import('../runtime').RunParams} RunParams */
/** @typedef {import('./types').Topic} Topic */
/** @typedef {import('./types').Request} Request */
/** @typedef {import('./types').Response} Response */
/** @typedef {import('./types').PubSub} PubSub */
/** @typedef {import('./types').Socket} Socket */

/**
 * @param {string} topic
 * @param {RunParams} params
 */
function topicKey (topic, params) {
  return `run:${params.testRun}:plan:${params.testPlan}:case:${params.testCase}:topics:${topic}`
}
/**
 * @param {import('winston').Logger} logger
 * @param {function():Promise<RunParams>} extractor
 * @param {PubSub} pubsub
 * @param {Socket} socket
 * @returns {Topic}
 */
function createTopic (logger, extractor, pubsub, socket) {
  return {
    publish: async (topic, payload) => {
      const params = await extractor()
      if (!params) {
        throw new Error('no run parameters provided')
      }

      logger.debug('publishing item on topic', { topic, payload })

      const key = topicKey(topic, params)
      logger.debug('resolved key for publish', { topic, key })

      const seq = await pubsub.publish(key, payload)
      logger.debug('successfully published item; sequence number obtained', { topic, seq })

      return seq
    },
    subscribe: async (topic) => {
      const params = await extractor()
      if (!params) {
        throw new Error('no run parameters provided')
      }

      const key = topicKey(topic, params)
      return pubsub.subscribe(key)
    }
  }
}

module.exports = {
  createTopic
}
