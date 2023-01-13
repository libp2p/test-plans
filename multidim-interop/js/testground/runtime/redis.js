import { createClient } from 'redis'

export async function redis (url) {
  const redisAddr = `redis://${url || 'redis:6379'}`

  console.log(`connect to redis: ${redisAddr}`)

  const redisClient = createClient({
    url: redisAddr
  })
  redisClient.on('error', (err) => console.error(`Redis Client Error: ${err}`))
  await redisClient.connect()
  // redis client::connect blocks until server is ready,
  // so no need to ping, something the Go version of this interop test does

  return redisClient
}
