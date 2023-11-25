import { setMaxListeners as nodeSetMaxListeners } from 'events';
/**
 * An implementation of a typed event target
 * etc
 */
export class TypedEventEmitter extends EventTarget {
    #listeners = new Map();
    listenerCount(type) {
        const listeners = this.#listeners.get(type);
        if (listeners == null) {
            return 0;
        }
        return listeners.length;
    }
    addEventListener(type, listener, options) {
        super.addEventListener(type, listener, options);
        let list = this.#listeners.get(type);
        if (list == null) {
            list = [];
            this.#listeners.set(type, list);
        }
        list.push({
            callback: listener,
            once: (options !== true && options !== false && options?.once) ?? false
        });
    }
    removeEventListener(type, listener, options) {
        super.removeEventListener(type.toString(), listener ?? null, options);
        let list = this.#listeners.get(type);
        if (list == null) {
            return;
        }
        list = list.filter(({ callback }) => callback !== listener);
        this.#listeners.set(type, list);
    }
    dispatchEvent(event) {
        const result = super.dispatchEvent(event);
        let list = this.#listeners.get(event.type);
        if (list == null) {
            return result;
        }
        list = list.filter(({ once }) => !once);
        this.#listeners.set(event.type, list);
        return result;
    }
    safeDispatchEvent(type, detail) {
        return this.dispatchEvent(new CustomEvent(type, detail));
    }
}
/**
 * CustomEvent is a standard event but it's not supported by node.
 *
 * Remove this when https://github.com/nodejs/node/issues/40678 is closed.
 *
 * Ref: https://developer.mozilla.org/en-US/docs/Web/API/CustomEvent
 */
class CustomEventPolyfill extends Event {
    /** Returns any custom data event was created with. Typically used for synthetic events. */
    detail;
    constructor(message, data) {
        super(message, data);
        // @ts-expect-error could be undefined
        this.detail = data?.detail;
    }
}
export const CustomEvent = globalThis.CustomEvent ?? CustomEventPolyfill;
// TODO: remove this in v1
export { TypedEventEmitter as EventEmitter };
// create a setMaxListeners that doesn't break browser usage
export const setMaxListeners = (n, ...eventTargets) => {
    try {
        nodeSetMaxListeners(n, ...eventTargets);
    }
    catch {
        // swallow error, gulp
    }
};
//# sourceMappingURL=events.js.map