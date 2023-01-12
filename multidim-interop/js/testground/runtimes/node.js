import { runtime } from '../runtime.js'

export default async function runner(redis) {
    const _redis = redis

    return {
        redis: function () {
            return _redis
        },

        exec: async function (path) {
            await runtime.createBarrier('testground::result')
            await import(path)
            return await runtime.waitOnBarrier('testground::result')
        },

        createBarrier: async function (name, value) {
            return await runtime.createBarrier(name, value)
        },
        resolveBarrier: async function (name, value) {
            return await runtime.resolveBarrier(name, value)
        },
        waitOnBarrier: async function (name) {
            return await runtime.waitOnBarrier(name)
        },

        stop: async() => {}
    }
}
