/// <reference types="node" />
import { setMaxListeners as nodeSetMaxListeners } from 'events';
export interface EventCallback<EventType> {
    (evt: EventType): void;
}
export interface EventObject<EventType> {
    handleEvent: EventCallback<EventType>;
}
export type EventHandler<EventType> = EventCallback<EventType> | EventObject<EventType>;
/**
 * Adds types to the EventTarget class. Hopefully this won't be necessary forever.
 *
 * https://github.com/microsoft/TypeScript/issues/28357
 * https://github.com/microsoft/TypeScript/issues/43477
 * https://github.com/microsoft/TypeScript/issues/299
 * etc
 */
export interface TypedEventTarget<EventMap extends Record<string, any>> extends EventTarget {
    addEventListener<K extends keyof EventMap>(type: K, listener: EventHandler<EventMap[K]> | null, options?: boolean | AddEventListenerOptions): void;
    listenerCount(type: string): number;
    removeEventListener<K extends keyof EventMap>(type: K, listener?: EventHandler<EventMap[K]> | null, options?: boolean | EventListenerOptions): void;
    removeEventListener(type: string, listener?: EventHandler<Event>, options?: boolean | EventListenerOptions): void;
    safeDispatchEvent<Detail>(type: keyof EventMap, detail: CustomEventInit<Detail>): boolean;
}
/**
 * An implementation of a typed event target
 * etc
 */
export declare class TypedEventEmitter<EventMap extends Record<string, any>> extends EventTarget implements TypedEventTarget<EventMap> {
    #private;
    listenerCount(type: string): number;
    addEventListener<K extends keyof EventMap>(type: K, listener: EventHandler<EventMap[K]> | null, options?: boolean | AddEventListenerOptions): void;
    removeEventListener<K extends keyof EventMap>(type: K, listener?: EventHandler<EventMap[K]> | null, options?: boolean | EventListenerOptions): void;
    dispatchEvent(event: Event): boolean;
    safeDispatchEvent<Detail>(type: keyof EventMap, detail: CustomEventInit<Detail>): boolean;
}
export declare const CustomEvent: {
    new <T>(type: string, eventInitDict?: CustomEventInit<T> | undefined): CustomEvent<T>;
    prototype: CustomEvent<any>;
};
export { TypedEventEmitter as EventEmitter };
export declare const setMaxListeners: typeof nodeSetMaxListeners;
//# sourceMappingURL=events.d.ts.map