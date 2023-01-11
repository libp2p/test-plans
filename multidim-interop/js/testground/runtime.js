export const runtime = {
    params: async function() {
        return process.env
    },

    _storage: {},
    load: async function (key) {
        return this._storage[key]
    },
    store: async function (key, value) {
        this._storage[key] = value
    },

    testResult: async function () {
        return await this._testResultPromise
    },
    setTestResult: async function(result) {
        this._testResultPromiseResolve(result)
    }
}
runtime._testResultPromise = new Promise((resolve) => runtime._testResultPromiseResolve = resolve)