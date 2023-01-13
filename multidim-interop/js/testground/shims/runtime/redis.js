export async function redis (url) {
    const redis_http_address = `http://${url || '127.0.0.1:8080'}`

    console.log(`use redis HTTP Proxy with address: ${redis_http_address}`)

    const client = {
        endpoint: `${redis_http_address}/runtime/redis`
    }
    const handler = {
        get(target, method) {
            return async function () {
                const args = Array.prototype.slice.call(arguments)
                const rpc = { method, args }

                const response = await fetch(target.endpoint, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(rpc)
                })

                return (await response.json()).element
            };
        }
    }

    return new Proxy(client, handler)
}
