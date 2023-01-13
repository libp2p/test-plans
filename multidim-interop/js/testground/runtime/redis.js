import { createClient } from 'redis'

export async function redis (url) {
    const redis_addr = `redis://${url || 'redis:6379'}`

    console.log(`connect to redis: ${redis_addr}`)

    const redisClient = createClient({
        url: redis_addr
    })
    redisClient.on('error', (err) => console.error(`Redis Client Error: ${err}`))
    await redisClient.connect()
    // redis client::connect blocks until server is ready,
    // so no need to ping, something the Go version of this interop test does

    return redisClient
}
