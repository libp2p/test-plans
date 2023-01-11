import { runtime } from '../runtime.js'

export default async function runner(redis) {
    const _redis = redis

    return {
        redis: function () {
            return _redis
        },

        load: async function (key) {
            return await runtime.load(key)
        },
        store: async function (key, value) {
            return await runtime.store(key, value)
        },

        exec: async function (path) {
            await import(path)
            return await runtime.testResult()
        },

        stop: async() => {}
    }
}
