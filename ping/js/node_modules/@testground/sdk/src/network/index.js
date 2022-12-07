'use strict'

const ipaddr = require('ipaddr.js')
const os = require('os')

const ALLOW_ALL = 'allow_all'
const DENY_ALL = 'deny_all'

/** @typedef {import('../runtime').RunEnv} RunEnv */
/** @typedef {import('../sync').SyncClient} SyncClient */
/** @typedef {import('./types').NetworkClient} NetworkClient */
/** @typedef {import('./types').Config} Config */

/**
 * Converts the configuration from the JavaScript lowerCamelCase version to the
 * Go CammelCase version. More about this is mentioned at
 * https://github.com/testground/sdk-go/pull/34
 *
 * @param {Config} config
 * @returns {Record<string, any>}
 */
function normalizeConfig (config) {
  if (typeof config !== 'object') {
    return config
  }

  if (Array.isArray(config)) {
    return config.map(normalizeConfig)
  }

  const parsed = /** @type {Record<string, any>} */({})

  for (const [key, value] of Object.entries(config)) {
    const newKey = key === 'IPv4' || key === 'IPv6'
      ? key
      : key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`) // to_snake_case

    parsed[newKey] = normalizeConfig(value)
  }

  return parsed
}

/**
 * @param {SyncClient} client
 * @param {RunEnv} runenv
 * @returns {NetworkClient}
 */
function newClient (client, runenv) {
  return {
    waitNetworkInitialized: async () => {
      const startEvent = {
        stage_start_event: {
          name: 'network-initialized',
          group: runenv.testGroupId
        }
      }

      await client.signalEvent(startEvent)

      if (runenv.testSidecar) {
        try {
          const barrier = await client.barrier('network-initialized', runenv.testInstanceCount)
          await barrier.wait
        } catch (err) {
          runenv.recordMessage('network initialisation failed')
          throw err
        }
      }

      const endEvent = {
        stage_end_event: {
          name: 'network-initialized',
          group: runenv.testGroupId
        }
      }

      await client.signalEvent(endEvent)

      runenv.recordMessage('network initialisation successful')
    },
    configureNetwork: async (config) => {
      if (!runenv.testSidecar) {
        runenv.logger.warn('ignoring network change request; running in a sidecar-less environment')
        return
      }

      if (!config.callbackState) {
        throw new Error('failed to configure network; no callback state provided')
      }

      const topic = `network:${os.hostname()}`
      const target = (!config.callbackTarget || config.callbackTarget === 0)
        ? runenv.testInstanceCount // Fall back to instance count on zero value.
        : config.callbackTarget

      await client.publishAndWait(topic, normalizeConfig(config), config.callbackState, target)
    },
    getDataNetworkIP: () => {
      if (!runenv.testSidecar) {
        // this must be a local:exec runner and we currently don't support
        // traffic shaping on it for now, just return the loopback address
        return '127.0.0.1'
      }

      const ifaces = getNetworkInterfaces()

      for (const { address, family } of ifaces) {
        if (family !== 'IPv4') {
          runenv.recordMessage(`ignoring non ip4 addr ${address}`)
        } else {
          const addr = ipaddr.parse(address)
          if (addr.match(runenv.testSubnet)) {
            runenv.recordMessage(`detected data network IP: ${address}`)
            return address
          } else {
            runenv.recordMessage(`${address} not in data subnet ${runenv.testSubnet.toString()}`)
          }
        }
      }

      throw new Error(`unable to determine data network IP. no interface found with IP in ${runenv.testSubnet.toString()}`)
    }
  }
}

/**
 * @returns {os.NetworkInterfaceInfo[]}
 */
function getNetworkInterfaces () {
  const v = os.networkInterfaces()
  if (!v) {
    return /** @type {os.NetworkInterfaceInfo[]} */([])
  }

  const ifaces = /** @type {os.NetworkInterfaceInfo[]} */([])
  for (const network in v) {
    if (v[network]) {
      // @ts-ignore
      ifaces.push(...v[network])
    }
  }

  return ifaces
}

module.exports = {
  ALLOW_ALL,
  DENY_ALL,
  newClient
}
