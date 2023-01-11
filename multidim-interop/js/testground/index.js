import { createClient } from 'redis'

import node from './runtimes/node.js'

export default async function test(fn) {
    const REDIS_ADDR = process.env.REDIS_ADDR || 'redis:6379'

    console.log(`connect to redis: redis://${REDIS_ADDR}`)

    const redisClient = createClient({
        url: `redis://${REDIS_ADDR}`
    })
    redisClient.on('error', (err) => console.error(`Redis Client Error: ${err}`))
    await redisClient.connect()
    // redis client::connect blocks until server is ready,
    // so no need to ping, something the Go version of this interop test does

    const RUNTIME = process.env.TEST_RUNTIME || 'node'  // other options: chromium, firefox, webkit

    try {
        let runner
        if (RUNTIME === 'node') {
            runner = await node(redisClient)
        } else if (['chromium', 'firefox', 'webkit'].indexOf(RUNTIME) >= 0) {
            throw new Error('TODO: implement browser runtime')
        } else {
            throw new Error(`Unknown runtime: ${RUNTIME}`)
        }

        try {
            await fn(runner)
        } finally {
            await runner.stop()
        }
    } finally {
        await redisClient.disconnect()
        console.log(`redis disconnected: redis://${REDIS_ADDR}`)
    }

    console.log('Clean Exit, Bye!')
}
