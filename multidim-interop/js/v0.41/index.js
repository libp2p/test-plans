import { createClient } from 'redis'

import { createLibp2p } from 'libp2p'
import { tcp } from '@libp2p/tcp'
import { webSockets } from '@libp2p/websockets'
import { noise } from '@chainsafe/libp2p-noise'
import { mplex } from '@libp2p/mplex'
import { yamux } from '@chainsafe/libp2p-yamux'
import { multiaddr } from '@multiformats/multiaddr'

(async () => {
    const TRANSPORT = process.env.transport
    const SECURE_CHANNEL = process.env.security
    const MUXER = process.env.muxer
    const IS_DIALER_STR = process.env.is_dialer
    const IP = process.env.ip
    const REDIS_ADDR = process.env.REDIS_ADDR || 'redis:6379'

    console.log(`connect to redis: redis://${REDIS_ADDR}`)

    const redisClient = createClient({
        url: `redis://${REDIS_ADDR}`
    })
    redisClient.on('error', (err) => console.error(`Redis Client Error: ${err}`))
    await redisClient.connect()
    // redis client::connect blocks until server is ready,
    // so no need to ping, something the Go version of this interop test does

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
        console.log(`node ${node.peerId} pings: ${otherMa}`)
        await node.ping(multiaddr(otherMa))
            .then((rtt) => console.log(`Ping successful: ${rtt}`))
            .then(() => redisClient.rPush('dialerDone', ''))
    } else {
        const multiaddrs = node.getMultiaddrs().map(ma => ma.toString()).filter(maString => !maString.includes("127.0.0.1"))
        console.log("My multiaddrs are", multiaddrs)
        await redisClient.rPush('listenerAddr', multiaddrs[0])
        await redisClient.blPop('dialerDone', 10)
    }

    try {
        // We don't care if these fail
        await node.stop()
        await redisClient.disconnect()
    } catch { }
})()
