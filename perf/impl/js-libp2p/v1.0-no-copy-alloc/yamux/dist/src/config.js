import { CodeError } from '@libp2p/interface/errors';
import { logger } from '@libp2p/logger';
import { ERR_INVALID_CONFIG, INITIAL_STREAM_WINDOW, MAX_STREAM_WINDOW } from './constants.js';
export const defaultConfig = {
    log: logger('libp2p:yamux'),
    enableKeepAlive: true,
    keepAliveInterval: 30000,
    maxInboundStreams: 1000,
    maxOutboundStreams: 1000,
    initialStreamWindowSize: INITIAL_STREAM_WINDOW,
    maxStreamWindowSize: MAX_STREAM_WINDOW,
    maxMessageSize: 64 * 1024
};
export function verifyConfig(config) {
    if (config.keepAliveInterval <= 0) {
        throw new CodeError('keep-alive interval must be positive', ERR_INVALID_CONFIG);
    }
    if (config.maxInboundStreams < 0) {
        throw new CodeError('max inbound streams must be larger or equal 0', ERR_INVALID_CONFIG);
    }
    if (config.maxOutboundStreams < 0) {
        throw new CodeError('max outbound streams must be larger or equal 0', ERR_INVALID_CONFIG);
    }
    if (config.initialStreamWindowSize < INITIAL_STREAM_WINDOW) {
        throw new CodeError('InitialStreamWindowSize must be larger or equal 256 kB', ERR_INVALID_CONFIG);
    }
    if (config.maxStreamWindowSize < config.initialStreamWindowSize) {
        throw new CodeError('MaxStreamWindowSize must be larger than the InitialStreamWindowSize', ERR_INVALID_CONFIG);
    }
    if (config.maxStreamWindowSize > 2 ** 32 - 1) {
        throw new CodeError('MaxStreamWindowSize must be less than equal MAX_UINT32', ERR_INVALID_CONFIG);
    }
    if (config.maxMessageSize < 1024) {
        throw new CodeError('MaxMessageSize must be greater than a kilobyte', ERR_INVALID_CONFIG);
    }
}
//# sourceMappingURL=config.js.map