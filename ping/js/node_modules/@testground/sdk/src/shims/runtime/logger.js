/* eslint-disable no-console */
'use strict'

// Loosely based on Winston's Logger logic,
// simplified for our minimal needs.
// See license at https://github.com/winstonjs/winston/blob/master/LICENSE
// for original source code.

function getLogger () {
  return {
    /**
     * @param {any[]} args
     */
    debug (...args) {
      return this.log(console.debug, ...args)
    },

    /**
     * @param {any[]} args
     */
    info (...args) {
      return this.log(console.info, ...args)
    },

    /**
     * @param {any[]} args
     */
    warn (...args) {
      return this.log(console.warn, ...args)
    },

    /**
     * @param {any[]} args
     */
    error (...args) {
      return this.log(console.error, ...args)
    },

    /**
     * @param {CallableFunction} fn
     * @param {any[]} args
     */
    log (fn, ...args) {
      // Optimize the hot-path which is the single object.
      if (args.length === 1) {
        const [msg] = args
        const info = (msg && msg.message && msg) || { message: msg }
        this._write(fn, info)
        return this
      }

      // When provided nothing assume the empty string
      if (args.length === 0) {
        this._log(fn, '')
        return this
      }

      // Otherwise build argument list
      return this._log(fn, args[0], ...args.slice(1))
    },

    /**
     * @param {CallableFunction} fn
     * @param {any} msg
     * @param {any[]} splat
     */
    _log (fn, msg, ...splat) {
      // eslint-disable-line max-params
      // Optimize for the hotpath of logging JSON literals
      if (arguments.length === 1) {
        this._write(fn, '')
        return this
      }

      // Slightly less hotpath, but worth optimizing for.
      if (arguments.length === 2) {
        if (msg && typeof msg === 'object') {
          this._write(fn, msg)
          return this
        }

        this._write(fn, { message: msg })
        return this
      }

      this._write(fn, { message: msg, splat })
      return this
    },

    /**
     * @param {CallableFunction} fn
     * @param {any} msg
     */
    _write (fn, msg) {
      const s = JSON.stringify(msg)
      fn(s)
    }
  }
}

module.exports = {
  getLogger
}
