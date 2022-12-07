'use strict'

/** @typedef {import('./types').RunParams} RunParams */
/** @typedef {import('./types').SignalEmitter} SignalEmitter */
/** @typedef {import('./types').Events} Events */
/** @typedef {import('winston').Logger} Logger */

/**
 * @param {RunParams} runParams
 * @param {Logger} logger
 * @param {function():SignalEmitter|null} getSignalEmitter
 * @returns {Events}
 */
function newEvents (runParams, logger, getSignalEmitter) {
  /**
   * @param {Object} event
   */
  const emitEvent = async (event) => {
    const signalEmitter = getSignalEmitter()

    if (!signalEmitter) {
      return
    }

    try {
      await signalEmitter.signalEvent(event)
    } catch (_) {}
  }

  return {
    recordMessage: (msg) => {
      const event = {
        message_event: {
          message: msg
        }
      }

      logger.info('', { event })
      return emitEvent(event)
    },
    recordStart: () => {
      const event = {
        start_event: {
          runenv: runParams
        }
      }

      logger.info('', { event })
      return emitEvent(event)
    },
    recordSuccess: () => {
      const event = {
        success_event: {
          group: runParams.testGroupId
        }
      }

      logger.info('', { event })
      return emitEvent(event)
    },
    recordFailure: (err) => {
      const event = {
        failure_event: {
          group: runParams.testGroupId,
          error: err.toString()
        }
      }

      logger.info('', { event })
      return emitEvent(event)
    },
    recordCrash: (err) => {
      const event = {
        crash_event: {
          group: runParams.testGroupId,
          error: err.toString(),
          stacktrace: err.stack
        }
      }

      logger.info('', { event })
      return emitEvent(event)
    }
  }
}

module.exports = {
  newEvents
}
