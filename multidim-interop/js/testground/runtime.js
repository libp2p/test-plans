export const runtime = {
    params: async function() {
        return process.env
    },

    _barriers: {},
    createBarrier: async function (name, value) {
        if (name in this._barriers) {
            throw new Error(`barrier with name ${name} already exists`)
        }
        this._barriers[name] = {}
        this._barriers[name].promise = new Promise((resolve) => {
            console.log(`created barrier with name ${name}`)
            this._barriers[name].resolve = resolve
            if (value !== undefined) {
                this.resolveBarrier(name, value)
            }
        })
    },
    resolveBarrier: async function (name, value) {
        if (!(name in this._barriers)) {
            throw new Error(`barrier with name ${name} does not exist`)
        }
        console.log(`resolve barrier with name ${name}`)
        this._barriers[name].resolve(value)
    },
    waitOnBarrier: async function (name) {
        if (!(name in this._barriers)) {
            throw new Error(`barrier with name ${name} does not exist`)
        }
        console.log(`wait on barrier with name ${name}`)
        return await this._barriers[name].promise
    }
}
runtime._testResultPromise = new Promise((resolve) => runtime._testResultPromiseResolve = resolve)