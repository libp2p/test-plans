import { redis, getParams, logger, markTestAsCompleted } from 'wo-testground/runtime/index.js'

import { createLibp2p } from 'libp2p'
import { tcp } from '@libp2p/tcp'
import { webSockets } from '@libp2p/websockets'
import { noise } from '@chainsafe/libp2p-noise'
import { mplex } from '@libp2p/mplex'
import { yamux } from '@chainsafe/libp2p-yamux'
import { multiaddr } from '@multiformats/multiaddr'

; (async () => {
  const params = await getParams()

  const TRANSPORT = params.transport
  const SECURE_CHANNEL = params.security
  const MUXER = params.muxer
  const IS_DIALER_STR = params.is_dialer
  const IP = params.ip
  const REDIS_ADDR = params.REDIS_ADDR

  const redisClient = await redis(REDIS_ADDR)

  const isDialer = IS_DIALER_STR === 'true'
  const options = {
    start: true
  }

  switch (TRANSPORT) {
    case 'tcp':
      options.transports = [tcp()]
      options.addresses = {
        listen: [`/ip4/${IP}/tcp/0`]
      }
      break
    case 'ws':
      options.transports = [webSockets()]
      options.addresses = {
        listen: [`/ip4/${IP}/tcp/0/ws`]
      }
      break
    default:
      throw new Error(`Unknown transport: ${TRANSPORT}`)
  }

  switch (SECURE_CHANNEL) {
    case 'noise':
      options.connectionEncryption = [noise()]
      break
    default:
      throw new Error(`Unknown secure channel: ${TRANSPORT}`)
  }

  switch (MUXER) {
    case 'mplex':
      options.streamMuxers = [mplex()]
      break
    case 'yamux':
      options.streamMuxers = [yamux()]
      break
    default:
      throw new Error(`Unknown muxer: ${MUXER}`)
  }

  const node = await createLibp2p(options)

  if (isDialer) {
    const otherMa = (await redisClient.blPop('listenerAddr', 10)).element
    logger.info(`node ${node.peerId} pings: ${otherMa}`)
    await node.ping(multiaddr(otherMa))
      .then((rtt) => logger.info(`Ping successful: ${rtt}`))
      .then(() => redisClient.rPush('dialerDone', ''))
  } else {
    const multiaddrs = node.getMultiaddrs().map(ma => ma.toString()).filter(maString => !maString.includes('127.0.0.1'))
    logger.info('My multiaddrs are', multiaddrs)
    await redisClient.rPush('listenerAddr', multiaddrs[0])
    await redisClient.blPop('dialerDone', 4)
  }

  // We don't care if these fail
  try {
    await node.stop()
  } catch (error) {
    logger.error('stop libp2p node:', error)
  }
  try {
    await redisClient.disconnect()
  } catch (error) {
    logger.error('stop redis client:', error)
  }

  await markTestAsCompleted('LibP2P::test', true)
})()
