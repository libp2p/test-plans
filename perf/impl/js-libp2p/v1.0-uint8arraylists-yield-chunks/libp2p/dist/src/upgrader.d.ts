import type { Libp2pEvents, ComponentLogger } from '@libp2p/interface';
import type { MultiaddrConnection, Connection, Stream, ConnectionProtector } from '@libp2p/interface/connection';
import type { ConnectionEncrypter, SecuredConnection } from '@libp2p/interface/connection-encrypter';
import type { ConnectionGater } from '@libp2p/interface/connection-gater';
import type { TypedEventTarget } from '@libp2p/interface/events';
import type { Metrics } from '@libp2p/interface/metrics';
import type { PeerId } from '@libp2p/interface/peer-id';
import type { PeerStore } from '@libp2p/interface/peer-store';
import type { StreamMuxerFactory } from '@libp2p/interface/stream-muxer';
import type { Upgrader, UpgraderOptions } from '@libp2p/interface/transport';
import type { ConnectionManager } from '@libp2p/interface-internal/connection-manager';
import type { Registrar } from '@libp2p/interface-internal/registrar';
interface CreateConnectionOptions {
    cryptoProtocol: string;
    direction: 'inbound' | 'outbound';
    maConn: MultiaddrConnection;
    upgradedConn: MultiaddrConnection;
    remotePeer: PeerId;
    muxerFactory?: StreamMuxerFactory;
    transient?: boolean;
}
interface OnStreamOptions {
    connection: Connection;
    stream: Stream;
    protocol: string;
}
export interface CryptoResult extends SecuredConnection<MultiaddrConnection> {
    protocol: string;
}
export interface UpgraderInit {
    connectionEncryption: ConnectionEncrypter[];
    muxers: StreamMuxerFactory[];
    /**
     * An amount of ms by which an inbound connection upgrade
     * must complete
     */
    inboundUpgradeTimeout?: number;
}
export interface DefaultUpgraderComponents {
    peerId: PeerId;
    metrics?: Metrics;
    connectionManager: ConnectionManager;
    connectionGater: ConnectionGater;
    connectionProtector?: ConnectionProtector;
    registrar: Registrar;
    peerStore: PeerStore;
    events: TypedEventTarget<Libp2pEvents>;
    logger: ComponentLogger;
}
type ConnectionDeniedType = keyof Pick<ConnectionGater, 'denyOutboundConnection' | 'denyInboundEncryptedConnection' | 'denyOutboundEncryptedConnection' | 'denyInboundUpgradedConnection' | 'denyOutboundUpgradedConnection'>;
export declare class DefaultUpgrader implements Upgrader {
    private readonly components;
    private readonly connectionEncryption;
    private readonly muxers;
    private readonly inboundUpgradeTimeout;
    private readonly events;
    private readonly log;
    constructor(components: DefaultUpgraderComponents, init: UpgraderInit);
    shouldBlockConnection(remotePeer: PeerId, maConn: MultiaddrConnection, connectionType: ConnectionDeniedType): Promise<void>;
    /**
     * Upgrades an inbound connection
     */
    upgradeInbound(maConn: MultiaddrConnection, opts?: UpgraderOptions): Promise<Connection>;
    /**
     * Upgrades an outbound connection
     */
    upgradeOutbound(maConn: MultiaddrConnection, opts?: UpgraderOptions): Promise<Connection>;
    /**
     * A convenience method for generating a new `Connection`
     */
    _createConnection(opts: CreateConnectionOptions): Connection;
    /**
     * Routes incoming streams to the correct handler
     */
    _onStream(opts: OnStreamOptions): void;
    /**
     * Attempts to encrypt the incoming `connection` with the provided `cryptos`
     */
    _encryptInbound(connection: MultiaddrConnection): Promise<CryptoResult>;
    /**
     * Attempts to encrypt the given `connection` with the provided connection encrypters.
     * The first `ConnectionEncrypter` module to succeed will be used
     */
    _encryptOutbound(connection: MultiaddrConnection, remotePeerId?: PeerId): Promise<CryptoResult>;
    /**
     * Selects one of the given muxers via multistream-select. That
     * muxer will be used for all future streams on the connection.
     */
    _multiplexOutbound(connection: MultiaddrConnection, muxers: Map<string, StreamMuxerFactory>): Promise<{
        stream: MultiaddrConnection;
        muxerFactory?: StreamMuxerFactory;
    }>;
    /**
     * Registers support for one of the given muxers via multistream-select. The
     * selected muxer will be used for all future streams on the connection.
     */
    _multiplexInbound(connection: MultiaddrConnection, muxers: Map<string, StreamMuxerFactory>): Promise<{
        stream: MultiaddrConnection;
        muxerFactory?: StreamMuxerFactory;
    }>;
}
export {};
//# sourceMappingURL=upgrader.d.ts.map