import { createLibp2p } from 'libp2p'
import { tcp } from '@libp2p/tcp'
import { webSockets } from '@libp2p/websockets'
import { noise } from '@chainsafe/libp2p-noise'
import { mplex } from '@libp2p/mplex'
import { yamux } from '@chainsafe/libp2p-yamux'
import { multiaddr } from '@multiformats/multiaddr'

import { runtime } from 'wo-testground/runtime.js'

(async () => {
    const params = await runtime.params()

    const IS_DIALER_STR = params.is_dialer
    const isDialer = IS_DIALER_STR === 'true'

    const TRANSPORT = params.transport
    const SECURE_CHANNEL = params.security
    const MUXER = params.muxer
    const IP = params.ip

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
    console.log(`node ${node.peerId} created...`)

    if (isDialer) {
        const otherMa = await runtime.waitOnBarrier('otherMultiAddress')
        console.log(`node ${node.peerId} pings: ${otherMa}`)
        await node.ping(multiaddr(otherMa))
            .then((rtt) => console.log(`Ping successful: ${rtt}`))
    } else {
        const multiaddrs = node
            .getMultiaddrs()
            .map(ma => ma.toString())
            .filter(maString => !maString.includes("127.0.0.1"))
        await runtime.resolveBarrier('multiAddress', multiaddrs[0])
        await runtime.waitOnBarrier('dialerDone')
    }

    try {
        // We don't care if these fail
        await node.stop()
    } catch (error) {
        console.error('node::stop', error)
    }

    await runtime.resolveBarrier('testground::result', true)
})()
