'use strict'

const Emittery = require('emittery')
const WebSocket = require('isomorphic-ws')

const {
  ENV_SYNC_SERVICE_HOST,
  ENV_SYNC_SERVICE_PORT
} = require('../env/sync')
const {
  getEnvParameters
} = require('../env')

/** @typedef {import('winston').Logger} Logger */
/** @typedef {import('events').EventEmitter} EventEmitter */
/** @typedef {import('../runtime').RunEnv} RunEnv */
/** @typedef {import('../runtime').RunParams} RunParams */
/** @typedef {import('./types').SyncClient} SyncClient */
/** @typedef {import('./types').Request} Request */
/** @typedef {import('./types').Response} Response */
/** @typedef {import('./types').ResponseIterator} ResponseIterator */
/** @typedef {import('./types').Socket} Socket */

/**
 * @param {import('winston').Logger} logger
 * @returns {Promise<Socket>}
 */
function createSocket (logger) {
  const address = socketAddress()
  const ws = new WebSocket(address)
  const emitter = new Emittery()
  let next = 0

  return new Promise((resolve, reject) => {
    ws.onopen = function open () {
      resolve({
        request,
        requestOnce,
        close: () => {
          ws.close()
        }
      })
    }

    ws.onclose = function close () {
      logger.debug('connection to sync server closed')
    }

    ws.onmessage = function incoming (event) {
      const res = /** @type Response */(JSON.parse(event.data.toString()))
      emitter.emit(res.id, res)
    }

    /**
     * @param {Request} req
     * @returns {Promise<Response>}
     */
    const requestOnce = async function (req) {
      const id = (next++).toString()
      const promise = emitter.once(id)

      req.id = id
      ws.send(JSON.stringify(req))

      const data = await promise
      return data
    }

    /**
     * @param {Request} req
     * @returns {ResponseIterator}
     */
    const request = function (req) {
      const id = (next++).toString()
      const it = emitter.events(id)
      let run = true

      req.id = id
      ws.send(JSON.stringify(req))

      const cancel = () => {
        run = false
        emitter.clearListeners(id)
      }

      const wait = (async function * () {
        try {
          for await (const data of it) {
            yield data
          }
        } catch (e) {
          if (run) throw e
        }
      })()

      return {
        cancel,
        wait
      }
    }
  })
}

function socketAddress () {
  const env = getEnvParameters()

  let host = env[ENV_SYNC_SERVICE_HOST]
  let port = env[ENV_SYNC_SERVICE_PORT]

  if (!port) {
    port = '5050'
  }

  if (!host) {
    host = 'testground-sync-service'
  }

  return `ws://${host}:${port}`
}

module.exports = {
  createSocket
}
