import { CodeError } from '@libp2p/interface/errors';
import { setMaxListeners } from '@libp2p/interface/events';
import * as mss from '@libp2p/multistream-select';
import { peerIdFromString } from '@libp2p/peer-id';
import { createConnection } from './connection/index.js';
import { INBOUND_UPGRADE_TIMEOUT } from './connection-manager/constants.js';
import { codes } from './errors.js';
import { DEFAULT_MAX_INBOUND_STREAMS, DEFAULT_MAX_OUTBOUND_STREAMS } from './registrar.js';
const ERR_TIMEOUT = 'ERR_TIMEOUT';
const DEFAULT_PROTOCOL_SELECT_TIMEOUT = 30000;
function findIncomingStreamLimit(protocol, registrar) {
    try {
        const { options } = registrar.getHandler(protocol);
        return options.maxInboundStreams;
    }
    catch (err) {
        if (err.code !== codes.ERR_NO_HANDLER_FOR_PROTOCOL) {
            throw err;
        }
    }
    return DEFAULT_MAX_INBOUND_STREAMS;
}
function findOutgoingStreamLimit(protocol, registrar, options = {}) {
    try {
        const { options } = registrar.getHandler(protocol);
        if (options.maxOutboundStreams != null) {
            return options.maxOutboundStreams;
        }
    }
    catch (err) {
        if (err.code !== codes.ERR_NO_HANDLER_FOR_PROTOCOL) {
            throw err;
        }
    }
    return options.maxOutboundStreams ?? DEFAULT_MAX_OUTBOUND_STREAMS;
}
function countStreams(protocol, direction, connection) {
    let streamCount = 0;
    connection.streams.forEach(stream => {
        if (stream.direction === direction && stream.protocol === protocol) {
            streamCount++;
        }
    });
    return streamCount;
}
export class DefaultUpgrader {
    components;
    connectionEncryption;
    muxers;
    inboundUpgradeTimeout;
    events;
    logger;
    log;
    constructor(components, init) {
        this.components = components;
        this.connectionEncryption = new Map();
        this.log = components.logger.forComponent('libp2p:upgrader');
        this.logger = components.logger;
        init.connectionEncryption.forEach(encrypter => {
            this.connectionEncryption.set(encrypter.protocol, encrypter);
        });
        this.muxers = new Map();
        init.muxers.forEach(muxer => {
            this.muxers.set(muxer.protocol, muxer);
        });
        this.inboundUpgradeTimeout = init.inboundUpgradeTimeout ?? INBOUND_UPGRADE_TIMEOUT;
        this.events = components.events;
    }
    async shouldBlockConnection(remotePeer, maConn, connectionType) {
        const connectionGater = this.components.connectionGater[connectionType];
        if (connectionGater !== undefined) {
            if (await connectionGater(remotePeer, maConn)) {
                throw new CodeError(`The multiaddr connection is blocked by gater.${connectionType}`, codes.ERR_CONNECTION_INTERCEPTED);
            }
        }
    }
    /**
     * Upgrades an inbound connection
     */
    async upgradeInbound(maConn, opts) {
        const accept = await this.components.connectionManager.acceptIncomingConnection(maConn);
        if (!accept) {
            throw new CodeError('connection denied', codes.ERR_CONNECTION_DENIED);
        }
        let encryptedConn;
        let remotePeer;
        let upgradedConn;
        let muxerFactory;
        let cryptoProtocol;
        const signal = AbortSignal.timeout(this.inboundUpgradeTimeout);
        const onAbort = () => {
            maConn.abort(new CodeError('inbound upgrade timeout', ERR_TIMEOUT));
        };
        signal.addEventListener('abort', onAbort, { once: true });
        setMaxListeners(Infinity, signal);
        try {
            if ((await this.components.connectionGater.denyInboundConnection?.(maConn)) === true) {
                throw new CodeError('The multiaddr connection is blocked by gater.acceptConnection', codes.ERR_CONNECTION_INTERCEPTED);
            }
            this.components.metrics?.trackMultiaddrConnection(maConn);
            this.log('starting the inbound connection upgrade');
            // Protect
            let protectedConn = maConn;
            if (opts?.skipProtection !== true) {
                const protector = this.components.connectionProtector;
                if (protector != null) {
                    this.log('protecting the inbound connection');
                    protectedConn = await protector.protect(maConn);
                }
            }
            try {
                // Encrypt the connection
                encryptedConn = protectedConn;
                if (opts?.skipEncryption !== true) {
                    ({
                        conn: encryptedConn,
                        remotePeer,
                        protocol: cryptoProtocol
                    } = await this._encryptInbound(protectedConn));
                    const maConn = {
                        ...protectedConn,
                        ...encryptedConn
                    };
                    await this.shouldBlockConnection(remotePeer, maConn, 'denyInboundEncryptedConnection');
                }
                else {
                    const idStr = maConn.remoteAddr.getPeerId();
                    if (idStr == null) {
                        throw new CodeError('inbound connection that skipped encryption must have a peer id', codes.ERR_INVALID_MULTIADDR);
                    }
                    const remotePeerId = peerIdFromString(idStr);
                    cryptoProtocol = 'native';
                    remotePeer = remotePeerId;
                }
                upgradedConn = encryptedConn;
                if (opts?.muxerFactory != null) {
                    muxerFactory = opts.muxerFactory;
                }
                else if (this.muxers.size > 0) {
                    // Multiplex the connection
                    const multiplexed = await this._multiplexInbound({
                        ...protectedConn,
                        ...encryptedConn
                    }, this.muxers);
                    muxerFactory = multiplexed.muxerFactory;
                    upgradedConn = multiplexed.stream;
                }
            }
            catch (err) {
                this.log.error('Failed to upgrade inbound connection', err);
                throw err;
            }
            await this.shouldBlockConnection(remotePeer, maConn, 'denyInboundUpgradedConnection');
            this.log('successfully upgraded inbound connection');
            return this._createConnection({
                cryptoProtocol,
                direction: 'inbound',
                maConn,
                upgradedConn,
                muxerFactory,
                remotePeer,
                transient: opts?.transient
            });
        }
        finally {
            signal.removeEventListener('abort', onAbort);
            this.components.connectionManager.afterUpgradeInbound();
        }
    }
    /**
     * Upgrades an outbound connection
     */
    async upgradeOutbound(maConn, opts) {
        const idStr = maConn.remoteAddr.getPeerId();
        let remotePeerId;
        if (idStr != null) {
            remotePeerId = peerIdFromString(idStr);
            await this.shouldBlockConnection(remotePeerId, maConn, 'denyOutboundConnection');
        }
        let encryptedConn;
        let remotePeer;
        let upgradedConn;
        let cryptoProtocol;
        let muxerFactory;
        this.components.metrics?.trackMultiaddrConnection(maConn);
        this.log('Starting the outbound connection upgrade');
        // If the transport natively supports encryption, skip connection
        // protector and encryption
        // Protect
        let protectedConn = maConn;
        if (opts?.skipProtection !== true) {
            const protector = this.components.connectionProtector;
            if (protector != null) {
                protectedConn = await protector.protect(maConn);
            }
        }
        try {
            // Encrypt the connection
            encryptedConn = protectedConn;
            if (opts?.skipEncryption !== true) {
                ({
                    conn: encryptedConn,
                    remotePeer,
                    protocol: cryptoProtocol
                } = await this._encryptOutbound(protectedConn, remotePeerId));
                const maConn = {
                    ...protectedConn,
                    ...encryptedConn
                };
                await this.shouldBlockConnection(remotePeer, maConn, 'denyOutboundEncryptedConnection');
            }
            else {
                if (remotePeerId == null) {
                    throw new CodeError('Encryption was skipped but no peer id was passed', codes.ERR_INVALID_PEER);
                }
                cryptoProtocol = 'native';
                remotePeer = remotePeerId;
            }
            upgradedConn = encryptedConn;
            if (opts?.muxerFactory != null) {
                muxerFactory = opts.muxerFactory;
            }
            else if (this.muxers.size > 0) {
                // Multiplex the connection
                const multiplexed = await this._multiplexOutbound({
                    ...protectedConn,
                    ...encryptedConn
                }, this.muxers);
                muxerFactory = multiplexed.muxerFactory;
                upgradedConn = multiplexed.stream;
            }
        }
        catch (err) {
            this.log.error('Failed to upgrade outbound connection', err);
            await maConn.close(err);
            throw err;
        }
        await this.shouldBlockConnection(remotePeer, maConn, 'denyOutboundUpgradedConnection');
        this.log('Successfully upgraded outbound connection');
        return this._createConnection({
            cryptoProtocol,
            direction: 'outbound',
            maConn,
            upgradedConn,
            muxerFactory,
            remotePeer,
            transient: opts?.transient
        });
    }
    /**
     * A convenience method for generating a new `Connection`
     */
    _createConnection(opts) {
        const { cryptoProtocol, direction, maConn, upgradedConn, remotePeer, muxerFactory, transient } = opts;
        let muxer;
        let newStream;
        let connection; // eslint-disable-line prefer-const
        if (muxerFactory != null) {
            // Create the muxer
            muxer = muxerFactory.createStreamMuxer({
                direction,
                // Run anytime a remote stream is created
                onIncomingStream: muxedStream => {
                    if (connection == null) {
                        return;
                    }
                    void Promise.resolve()
                        .then(async () => {
                        const protocols = this.components.registrar.getProtocols();
                        const { stream, protocol } = await mss.handle(muxedStream, protocols, {
                            log: muxedStream.log,
                            yieldBytes: false
                        });
                        if (connection == null) {
                            return;
                        }
                        connection.log('incoming stream opened on %s', protocol);
                        const incomingLimit = findIncomingStreamLimit(protocol, this.components.registrar);
                        const streamCount = countStreams(protocol, 'inbound', connection);
                        if (streamCount === incomingLimit) {
                            const err = new CodeError(`Too many inbound protocol streams for protocol "${protocol}" - limit ${incomingLimit}`, codes.ERR_TOO_MANY_INBOUND_PROTOCOL_STREAMS);
                            muxedStream.abort(err);
                            throw err;
                        }
                        // after the handshake the returned stream can have early data so override
                        // the souce/sink
                        muxedStream.source = stream.source;
                        muxedStream.sink = stream.sink;
                        muxedStream.protocol = protocol;
                        // If a protocol stream has been successfully negotiated and is to be passed to the application,
                        // the peerstore should ensure that the peer is registered with that protocol
                        await this.components.peerStore.merge(remotePeer, {
                            protocols: [protocol]
                        });
                        this.components.metrics?.trackProtocolStream(muxedStream, connection);
                        this._onStream({ connection, stream: muxedStream, protocol });
                    })
                        .catch(async (err) => {
                        this.log.error('error handling incoming stream id %s', muxedStream.id, err.message, err.code, err.stack);
                        if (muxedStream.timeline.close == null) {
                            await muxedStream.close();
                        }
                    });
                }
            });
            newStream = async (protocols, options = {}) => {
                if (muxer == null) {
                    throw new CodeError('Stream is not multiplexed', codes.ERR_MUXER_UNAVAILABLE);
                }
                connection.log('starting new stream for protocols [%s]', protocols);
                const muxedStream = await muxer.newStream();
                connection.log.trace('started new stream %s for protocols [%s]', muxedStream.id, protocols);
                try {
                    if (options.signal == null) {
                        this.log('No abort signal was passed while trying to negotiate protocols [%s] falling back to default timeout', protocols);
                        const signal = AbortSignal.timeout(DEFAULT_PROTOCOL_SELECT_TIMEOUT);
                        setMaxListeners(Infinity, signal);
                        options = {
                            ...options,
                            signal
                        };
                    }
                    let stream;
                    let protocol;
                    if (protocols.length === 1) {
                        connection.log.trace('starting stream for single protocol "%s", using lazy select', protocols[0]);
                        ({ stream, protocol } = mss.lazySelect(muxedStream, protocols[0], {
                            ...options,
                            log: muxedStream.log,
                            yieldBytes: false
                        }));
                    }
                    else {
                        connection.log.trace('starting new stream for protocols [%s], using regular select', protocols);
                        ({ stream, protocol } = await mss.select(muxedStream, protocols, {
                            ...options,
                            log: muxedStream.log,
                            yieldBytes: false
                        }));
                    }
                    connection.log('negotiated protocol stream %s with id %s', protocol, muxedStream.id);
                    const outgoingLimit = findOutgoingStreamLimit(protocol, this.components.registrar, options);
                    const streamCount = countStreams(protocol, 'outbound', connection);
                    if (streamCount >= outgoingLimit) {
                        const err = new CodeError(`Too many outbound protocol streams for protocol "${protocol}" - limit ${outgoingLimit}`, codes.ERR_TOO_MANY_OUTBOUND_PROTOCOL_STREAMS);
                        muxedStream.abort(err);
                        throw err;
                    }
                    // If a protocol stream has been successfully negotiated and is to be passed to the application,
                    // the peerstore should ensure that the peer is registered with that protocol
                    await this.components.peerStore.merge(remotePeer, {
                        protocols: [protocol]
                    });
                    // after the handshake the returned stream can have early data so override
                    // the souce/sink
                    muxedStream.source = stream.source;
                    muxedStream.sink = stream.sink;
                    muxedStream.protocol = protocol;
                    this.components.metrics?.trackProtocolStream(muxedStream, connection);
                    return muxedStream;
                }
                catch (err) {
                    connection.log.error('could not create new stream for protocols %s', protocols, err);
                    if (muxedStream.timeline.close == null) {
                        muxedStream.abort(err);
                    }
                    if (err.code != null) {
                        throw err;
                    }
                    throw new CodeError(String(err), codes.ERR_UNSUPPORTED_PROTOCOL);
                }
            };
            // Pipe all data through the muxer
            void Promise.all([
                muxer.sink(upgradedConn.source),
                upgradedConn.sink(muxer.source)
            ]).catch(err => {
                this.log.error(err);
            });
        }
        const _timeline = maConn.timeline;
        maConn.timeline = new Proxy(_timeline, {
            set: (...args) => {
                if (connection != null && args[1] === 'close' && args[2] != null && _timeline.close == null) {
                    // Wait for close to finish before notifying of the closure
                    (async () => {
                        try {
                            if (connection.status === 'open') {
                                await connection.close();
                            }
                        }
                        catch (err) {
                            this.log.error(err);
                        }
                        finally {
                            this.events.safeDispatchEvent('connection:close', {
                                detail: connection
                            });
                        }
                    })().catch(err => {
                        this.log.error(err);
                    });
                }
                return Reflect.set(...args);
            }
        });
        maConn.timeline.upgraded = Date.now();
        const errConnectionNotMultiplexed = () => {
            throw new CodeError('connection is not multiplexed', codes.ERR_CONNECTION_NOT_MULTIPLEXED);
        };
        // Create the connection
        connection = createConnection({
            remoteAddr: maConn.remoteAddr,
            remotePeer,
            status: 'open',
            direction,
            timeline: maConn.timeline,
            multiplexer: muxer?.protocol,
            encryption: cryptoProtocol,
            transient,
            logger: this.components.logger,
            newStream: newStream ?? errConnectionNotMultiplexed,
            getStreams: () => { if (muxer != null) {
                return muxer.streams;
            }
            else {
                return [];
            } },
            close: async (options) => {
                // Ensure remaining streams are closed gracefully
                if (muxer != null) {
                    this.log.trace('close muxer');
                    await muxer.close(options);
                }
                this.log.trace('close maconn');
                // close the underlying transport
                await maConn.close(options);
                this.log.trace('closed maconn');
            },
            abort: (err) => {
                maConn.abort(err);
                // Ensure remaining streams are aborted
                if (muxer != null) {
                    muxer.abort(err);
                }
            }
        });
        this.events.safeDispatchEvent('connection:open', {
            detail: connection
        });
        return connection;
    }
    /**
     * Routes incoming streams to the correct handler
     */
    _onStream(opts) {
        const { connection, stream, protocol } = opts;
        const { handler, options } = this.components.registrar.getHandler(protocol);
        if (connection.transient && options.runOnTransientConnection !== true) {
            throw new CodeError('Cannot open protocol stream on transient connection', 'ERR_TRANSIENT_CONNECTION');
        }
        handler({ connection, stream });
    }
    /**
     * Attempts to encrypt the incoming `connection` with the provided `cryptos`
     */
    async _encryptInbound(connection) {
        const protocols = Array.from(this.connectionEncryption.keys());
        this.log('handling inbound crypto protocol selection', protocols);
        try {
            const { stream, protocol } = await mss.handle(connection, protocols, {
                log: connection.log
            });
            const encrypter = this.connectionEncryption.get(protocol);
            if (encrypter == null) {
                throw new Error(`no crypto module found for ${protocol}`);
            }
            this.log('encrypting inbound connection using', protocol);
            return {
                ...await encrypter.secureInbound(this.components.peerId, stream),
                protocol
            };
        }
        catch (err) {
            throw new CodeError(String(err), codes.ERR_ENCRYPTION_FAILED);
        }
    }
    /**
     * Attempts to encrypt the given `connection` with the provided connection encrypters.
     * The first `ConnectionEncrypter` module to succeed will be used
     */
    async _encryptOutbound(connection, remotePeerId) {
        const protocols = Array.from(this.connectionEncryption.keys());
        this.log('selecting outbound crypto protocol', protocols);
        try {
            const { stream, protocol } = await mss.select(connection, protocols, {
                log: this.logger.forComponent('libp2p:mss:select')
            });
            const encrypter = this.connectionEncryption.get(protocol);
            if (encrypter == null) {
                throw new Error(`no crypto module found for ${protocol}`);
            }
            this.log('encrypting outbound connection to %p', remotePeerId);
            return {
                ...await encrypter.secureOutbound(this.components.peerId, stream, remotePeerId),
                protocol
            };
        }
        catch (err) {
            throw new CodeError(String(err), codes.ERR_ENCRYPTION_FAILED);
        }
    }
    /**
     * Selects one of the given muxers via multistream-select. That
     * muxer will be used for all future streams on the connection.
     */
    async _multiplexOutbound(connection, muxers) {
        const protocols = Array.from(muxers.keys());
        this.log('outbound selecting muxer %s', protocols);
        try {
            const { stream, protocol } = await mss.select(connection, protocols, {
                log: this.logger.forComponent('libp2p:mss:select')
            });
            this.log('%s selected as muxer protocol', protocol);
            const muxerFactory = muxers.get(protocol);
            return { stream, muxerFactory };
        }
        catch (err) {
            this.log.error('error multiplexing outbound stream', err);
            throw new CodeError(String(err), codes.ERR_MUXER_UNAVAILABLE);
        }
    }
    /**
     * Registers support for one of the given muxers via multistream-select. The
     * selected muxer will be used for all future streams on the connection.
     */
    async _multiplexInbound(connection, muxers) {
        const protocols = Array.from(muxers.keys());
        this.log('inbound handling muxers %s', protocols);
        try {
            const { stream, protocol } = await mss.handle(connection, protocols, {
                log: connection.log
            });
            const muxerFactory = muxers.get(protocol);
            return { stream, muxerFactory };
        }
        catch (err) {
            this.log.error('error multiplexing inbound stream', err);
            throw new CodeError(String(err), codes.ERR_MUXER_UNAVAILABLE);
        }
    }
}
//# sourceMappingURL=upgrader.js.map