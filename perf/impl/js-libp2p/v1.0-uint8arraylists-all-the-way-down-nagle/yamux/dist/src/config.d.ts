import { type Logger } from '@libp2p/logger';
export interface Config {
    /**
     * Used to control the log destination
     *
     * It can be disabled by explicitly setting to `undefined`
     */
    log?: Logger;
    /**
     * Used to do periodic keep alive messages using a ping.
     */
    enableKeepAlive: boolean;
    /**
     * How often to perform the keep alive
     *
     * measured in milliseconds
     */
    keepAliveInterval: number;
    /**
     * Maximum number of concurrent inbound streams that we accept.
     * If the peer tries to open more streams, those will be reset immediately.
     */
    maxInboundStreams: number;
    /**
     * Maximum number of concurrent outbound streams that we accept.
     * If the application tries to open more streams, the call to `newStream` will throw
     */
    maxOutboundStreams: number;
    /**
     * Used to control the initial window size that we allow for a stream.
     *
     * measured in bytes
     */
    initialStreamWindowSize: number;
    /**
     * Used to control the maximum window size that we allow for a stream.
     */
    maxStreamWindowSize: number;
    /**
     * Maximum size of a message that we'll send on a stream.
     * This ensures that a single stream doesn't hog a connection.
     */
    maxMessageSize: number;
}
export declare const defaultConfig: Config;
export declare function verifyConfig(config: Config): void;
//# sourceMappingURL=config.d.ts.map