import { createClient } from 'redis'

export default async function test() {
    console.log("Hello from testground")

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
        // ... TODO: create actual runtime...
    } finally {
        await redisClient.disconnect()
        console.log(`redis disconnected: redis://${REDIS_ADDR}`)
    }

    console.log('Clean Exit, Bye!')
}
