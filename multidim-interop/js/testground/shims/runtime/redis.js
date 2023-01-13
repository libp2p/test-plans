export async function redis (url) {
  const redisHttpAddress = `http://${url || '127.0.0.1:8080'}`

  console.log(`use redis HTTP Proxy with address: ${redisHttpAddress}`)

  const client = {
    endpoint: `${redisHttpAddress}/runtime/redis`
  }
  const handler = {
    get (target, method) {
      // TODO: either figure out why stuff like 'then' is called here, or make a more complete whitelist
      if (['blPop', 'rPush', 'disconnect'].indexOf(method) === -1) {
        return Reflect.get(...arguments)
      }
      console.log(`redis http proxy client: intercept method: ${method}`)
      return function () {
        const args = Array.prototype.slice.call(arguments)
        const rpc = { method, args }

        console.log(`redis http proxy client: make method call to ${method} with args: ${JSON.stringify(args)}`)

        return fetch(target.endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(rpc)
        }).then((response) => {
            console.log(`redis http proxy received response: ${response.status}`)
            return response.json()
        }).then((obj) => {
            console.log(`redis http proxy received Json response: ${JSON.stringify(obj)}`)
            return obj.output
        })
      }
    }
  }

  return new Proxy(client, handler)
}
