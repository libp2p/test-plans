import { CodeError } from '@libp2p/interface/errors';
import { isStartable } from '@libp2p/interface/startable';
import { defaultLogger } from '@libp2p/logger';
class DefaultComponents {
    components = {};
    _started = false;
    constructor(init = {}) {
        this.components = {};
        for (const [key, value] of Object.entries(init)) {
            this.components[key] = value;
        }
        if (this.components.logger == null) {
            this.components.logger = defaultLogger();
        }
    }
    isStarted() {
        return this._started;
    }
    async _invokeStartableMethod(methodName) {
        await Promise.all(Object.values(this.components)
            .filter(obj => isStartable(obj))
            .map(async (startable) => {
            await startable[methodName]?.();
        }));
    }
    async beforeStart() {
        await this._invokeStartableMethod('beforeStart');
    }
    async start() {
        await this._invokeStartableMethod('start');
        this._started = true;
    }
    async afterStart() {
        await this._invokeStartableMethod('afterStart');
    }
    async beforeStop() {
        await this._invokeStartableMethod('beforeStop');
    }
    async stop() {
        await this._invokeStartableMethod('stop');
        this._started = false;
    }
    async afterStop() {
        await this._invokeStartableMethod('afterStop');
    }
}
const OPTIONAL_SERVICES = [
    'metrics',
    'connectionProtector'
];
const NON_SERVICE_PROPERTIES = [
    'components',
    'isStarted',
    'beforeStart',
    'start',
    'afterStart',
    'beforeStop',
    'stop',
    'afterStop',
    'then',
    '_invokeStartableMethod'
];
export function defaultComponents(init = {}) {
    const components = new DefaultComponents(init);
    const proxy = new Proxy(components, {
        get(target, prop, receiver) {
            if (typeof prop === 'string' && !NON_SERVICE_PROPERTIES.includes(prop)) {
                const service = components.components[prop];
                if (service == null && !OPTIONAL_SERVICES.includes(prop)) {
                    throw new CodeError(`${prop} not set`, 'ERR_SERVICE_MISSING');
                }
                return service;
            }
            return Reflect.get(target, prop, receiver);
        },
        set(target, prop, value) {
            if (typeof prop === 'string') {
                components.components[prop] = value;
            }
            else {
                Reflect.set(target, prop, value);
            }
            return true;
        }
    });
    // @ts-expect-error component keys are proxied
    return proxy;
}
//# sourceMappingURL=components.js.map