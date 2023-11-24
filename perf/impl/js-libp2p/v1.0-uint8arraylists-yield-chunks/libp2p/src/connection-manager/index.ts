import { CodeError } from '@libp2p/interface/errors'
import { KEEP_ALIVE } from '@libp2p/interface/peer-store/tags'
import { PeerMap } from '@libp2p/peer-collections'
import { defaultAddressSort } from '@libp2p/utils/address-sort'
import { type Multiaddr, type Resolver, multiaddr } from '@multiformats/multiaddr'
import { dnsaddrResolver } from '@multiformats/multiaddr/resolvers'
import { RateLimiterMemory } from 'rate-limiter-flexible'
import { codes } from '../errors.js'
import { getPeerAddress } from '../get-peer.js'
import { AutoDial } from './auto-dial.js'
import { ConnectionPruner } from './connection-pruner.js'
import { AUTO_DIAL_CONCURRENCY, AUTO_DIAL_MAX_QUEUE_LENGTH, AUTO_DIAL_PRIORITY, DIAL_TIMEOUT, INBOUND_CONNECTION_THRESHOLD, MAX_CONNECTIONS, MAX_INCOMING_PENDING_CONNECTIONS, MAX_PARALLEL_DIALS, MAX_PEER_ADDRS_TO_DIAL, MIN_CONNECTIONS } from './constants.js'
import { DialQueue } from './dial-queue.js'
import type { PendingDial, AddressSorter, Libp2pEvents, AbortOptions, ComponentLogger, Logger } from '@libp2p/interface'
import type { Connection, MultiaddrConnection } from '@libp2p/interface/connection'
import type { ConnectionGater } from '@libp2p/interface/connection-gater'
import type { TypedEventTarget } from '@libp2p/interface/events'
import type { Metrics } from '@libp2p/interface/metrics'
import type { PeerId } from '@libp2p/interface/peer-id'
import type { Peer, PeerStore } from '@libp2p/interface/peer-store'
import type { Startable } from '@libp2p/interface/startable'
import type { ConnectionManager, OpenConnectionOptions } from '@libp2p/interface-internal/connection-manager'
import type { TransportManager } from '@libp2p/interface-internal/transport-manager'

const DEFAULT_DIAL_PRIORITY = 50

export interface ConnectionManagerInit {
  /**
   * The maximum number of connections libp2p is willing to have before it starts
   * pruning connections to reduce resource usage. (default: 300, 100 in browsers)
   */
  maxConnections?: number

  /**
   * The minimum number of connections below which libp2p will start to dial peers
   * from the peer book. Setting this to 0 effectively disables this behaviour.
   * (default: 50, 5 in browsers)
   */
  minConnections?: number

  /**
   * How long to wait between attempting to keep our number of concurrent connections
   * above minConnections (default: 5000)
   */
  autoDialInterval?: number

  /**
   * When dialling peers from the peer book to keep the number of open connections
   * above `minConnections`, add dials for this many peers to the dial queue
   * at once. (default: 25)
   */
  autoDialConcurrency?: number

  /**
   * To allow user dials to take priority over auto dials, use this value as the
   * dial priority. (default: 0)
   */
  autoDialPriority?: number

  /**
   * Limit the maximum number of peers to dial when trying to keep the number of
   * open connections above `minConnections`. (default: 100)
   */
  autoDialMaxQueueLength?: number

  /**
   * When we've failed to dial a peer, do not autodial them again within this
   * number of ms. (default: 1 minute, 7 minutes in browsers)
   */
  autoDialPeerRetryThreshold?: number

  /**
   * Newly discovered peers may be auto-dialed to increase the number of open
   * connections, but they can be discovered in quick succession so add a small
   * delay before attempting to dial them in case more peers have been
   * discovered. (default: 10ms)
   */
  autoDialDiscoveredPeersDebounce?: number

  /**
   * Sort the known addresses of a peer before trying to dial, By default public
   * addresses will be dialled before private (e.g. loopback or LAN) addresses.
   */
  addressSorter?: AddressSorter

  /**
   * The maximum number of dials across all peers to execute in parallel.
   * (default: 100, 50 in browsers)
   */
  maxParallelDials?: number

  /**
   * Maximum number of addresses allowed for a given peer - if a peer has more
   * addresses than this then the dial will fail. (default: 25)
   */
  maxPeerAddrsToDial?: number

  /**
   * How long a dial attempt is allowed to take, including DNS resolution
   * of the multiaddr, opening a socket and upgrading it to a Connection.
   */
  dialTimeout?: number

  /**
   * When a new inbound connection is opened, the upgrade process (e.g. protect,
   * encrypt, multiplex etc) must complete within this number of ms. (default: 30s)
   */
  inboundUpgradeTimeout?: number

  /**
   * Multiaddr resolvers to use when dialling
   */
  resolvers?: Record<string, Resolver>

  /**
   * A list of multiaddrs that will always be allowed (except if they are in the
   * deny list) to open connections to this node even if we've reached maxConnections
   */
  allow?: string[]

  /**
   * A list of multiaddrs that will never be allowed to open connections to
   * this node under any circumstances
   */
  deny?: string[]

  /**
   * If more than this many connections are opened per second by a single
   * host, reject subsequent connections. (default: 5)
   */
  inboundConnectionThreshold?: number

  /**
   * The maximum number of parallel incoming connections allowed that have yet to
   * complete the connection upgrade - e.g. choosing connection encryption, muxer, etc.
   * (default: 10)
   */
  maxIncomingPendingConnections?: number
}

const defaultOptions = {
  minConnections: MIN_CONNECTIONS,
  maxConnections: MAX_CONNECTIONS,
  inboundConnectionThreshold: INBOUND_CONNECTION_THRESHOLD,
  maxIncomingPendingConnections: MAX_INCOMING_PENDING_CONNECTIONS,
  autoDialConcurrency: AUTO_DIAL_CONCURRENCY,
  autoDialPriority: AUTO_DIAL_PRIORITY,
  autoDialMaxQueueLength: AUTO_DIAL_MAX_QUEUE_LENGTH
}

export interface DefaultConnectionManagerComponents {
  peerId: PeerId
  metrics?: Metrics
  peerStore: PeerStore
  transportManager: TransportManager
  connectionGater: ConnectionGater
  events: TypedEventTarget<Libp2pEvents>
  logger: ComponentLogger
}

/**
 * Responsible for managing known connections.
 */
export class DefaultConnectionManager implements ConnectionManager, Startable {
  private started: boolean
  private readonly connections: PeerMap<Connection[]>
  private readonly allow: Multiaddr[]
  private readonly deny: Multiaddr[]
  private readonly maxIncomingPendingConnections: number
  private incomingPendingConnections: number
  private readonly maxConnections: number

  public readonly dialQueue: DialQueue
  public readonly autoDial: AutoDial
  public readonly connectionPruner: ConnectionPruner
  private readonly inboundConnectionRateLimiter: RateLimiterMemory

  private readonly peerStore: PeerStore
  private readonly metrics?: Metrics
  private readonly events: TypedEventTarget<Libp2pEvents>
  private readonly log: Logger

  constructor (components: DefaultConnectionManagerComponents, init: ConnectionManagerInit = {}) {
    this.maxConnections = init.maxConnections ?? defaultOptions.maxConnections
    const minConnections = init.minConnections ?? defaultOptions.minConnections

    if (this.maxConnections < minConnections) {
      throw new CodeError('Connection Manager maxConnections must be greater than minConnections', codes.ERR_INVALID_PARAMETERS)
    }

    /**
     * Map of connections per peer
     */
    this.connections = new PeerMap()

    this.started = false
    this.peerStore = components.peerStore
    this.metrics = components.metrics
    this.events = components.events
    this.log = components.logger.forComponent('libp2p:connection-manager')

    this.onConnect = this.onConnect.bind(this)
    this.onDisconnect = this.onDisconnect.bind(this)
    this.events.addEventListener('connection:open', this.onConnect)
    this.events.addEventListener('connection:close', this.onDisconnect)

    // allow/deny lists
    this.allow = (init.allow ?? []).map(ma => multiaddr(ma))
    this.deny = (init.deny ?? []).map(ma => multiaddr(ma))

    this.incomingPendingConnections = 0
    this.maxIncomingPendingConnections = init.maxIncomingPendingConnections ?? defaultOptions.maxIncomingPendingConnections

    // controls individual peers trying to dial us too quickly
    this.inboundConnectionRateLimiter = new RateLimiterMemory({
      points: init.inboundConnectionThreshold ?? defaultOptions.inboundConnectionThreshold,
      duration: 1
    })

    // controls what happens when we don't have enough connections
    this.autoDial = new AutoDial({
      connectionManager: this,
      peerStore: components.peerStore,
      events: components.events,
      logger: components.logger
    }, {
      minConnections,
      autoDialConcurrency: init.autoDialConcurrency ?? defaultOptions.autoDialConcurrency,
      autoDialPriority: init.autoDialPriority ?? defaultOptions.autoDialPriority,
      maxQueueLength: init.autoDialMaxQueueLength ?? defaultOptions.autoDialMaxQueueLength
    })

    // controls what happens when we have too many connections
    this.connectionPruner = new ConnectionPruner({
      connectionManager: this,
      peerStore: components.peerStore,
      events: components.events,
      logger: components.logger
    }, {
      maxConnections: this.maxConnections,
      allow: this.allow
    })

    this.dialQueue = new DialQueue({
      peerId: components.peerId,
      metrics: components.metrics,
      peerStore: components.peerStore,
      transportManager: components.transportManager,
      connectionGater: components.connectionGater,
      logger: components.logger
    }, {
      addressSorter: init.addressSorter ?? defaultAddressSort,
      maxParallelDials: init.maxParallelDials ?? MAX_PARALLEL_DIALS,
      maxPeerAddrsToDial: init.maxPeerAddrsToDial ?? MAX_PEER_ADDRS_TO_DIAL,
      dialTimeout: init.dialTimeout ?? DIAL_TIMEOUT,
      resolvers: init.resolvers ?? {
        dnsaddr: dnsaddrResolver
      },
      connections: this.connections
    })
  }

  isStarted (): boolean {
    return this.started
  }

  /**
   * Starts the Connection Manager. If Metrics are not enabled on libp2p
   * only event loop and connection limits will be monitored.
   */
  async start (): Promise<void> {
    // track inbound/outbound connections
    this.metrics?.registerMetricGroup('libp2p_connection_manager_connections', {
      calculate: () => {
        const metric = {
          inbound: 0,
          outbound: 0
        }

        for (const conns of this.connections.values()) {
          for (const conn of conns) {
            if (conn.direction === 'inbound') {
              metric.inbound++
            } else {
              metric.outbound++
            }
          }
        }

        return metric
      }
    })

    // track total number of streams per protocol
    this.metrics?.registerMetricGroup('libp2p_protocol_streams_total', {
      label: 'protocol',
      calculate: () => {
        const metric: Record<string, number> = {}

        for (const conns of this.connections.values()) {
          for (const conn of conns) {
            for (const stream of conn.streams) {
              const key = `${stream.direction} ${stream.protocol ?? 'unnegotiated'}`

              metric[key] = (metric[key] ?? 0) + 1
            }
          }
        }

        return metric
      }
    })

    // track 90th percentile of streams per protocol
    this.metrics?.registerMetricGroup('libp2p_connection_manager_protocol_streams_per_connection_90th_percentile', {
      label: 'protocol',
      calculate: () => {
        const allStreams: Record<string, number[]> = {}

        for (const conns of this.connections.values()) {
          for (const conn of conns) {
            const streams: Record<string, number> = {}

            for (const stream of conn.streams) {
              const key = `${stream.direction} ${stream.protocol ?? 'unnegotiated'}`

              streams[key] = (streams[key] ?? 0) + 1
            }

            for (const [protocol, count] of Object.entries(streams)) {
              allStreams[protocol] = allStreams[protocol] ?? []
              allStreams[protocol].push(count)
            }
          }
        }

        const metric: Record<string, number> = {}

        for (let [protocol, counts] of Object.entries(allStreams)) {
          counts = counts.sort((a, b) => a - b)

          const index = Math.floor(counts.length * 0.9)
          metric[protocol] = counts[index]
        }

        return metric
      }
    })

    this.autoDial.start()

    this.started = true
    this.log('started')
  }

  async afterStart (): Promise<void> {
    // re-connect to any peers with the KEEP_ALIVE tag
    void Promise.resolve()
      .then(async () => {
        const keepAlivePeers: Peer[] = await this.peerStore.all({
          filters: [(peer) => {
            return peer.tags.has(KEEP_ALIVE)
          }]
        })

        await Promise.all(
          keepAlivePeers.map(async peer => {
            await this.openConnection(peer.id)
              .catch(err => {
                this.log.error(err)
              })
          })
        )
      })
      .catch(err => {
        this.log.error(err)
      })

    this.autoDial.afterStart()
  }

  /**
   * Stops the Connection Manager
   */
  async stop (): Promise<void> {
    this.dialQueue.stop()
    this.autoDial.stop()

    // Close all connections we're tracking
    const tasks: Array<Promise<void>> = []
    for (const connectionList of this.connections.values()) {
      for (const connection of connectionList) {
        tasks.push((async () => {
          try {
            await connection.close()
          } catch (err) {
            this.log.error(err)
          }
        })())
      }
    }

    this.log('closing %d connections', tasks.length)
    await Promise.all(tasks)
    this.connections.clear()

    this.log('stopped')
  }

  onConnect (evt: CustomEvent<Connection>): void {
    void this._onConnect(evt).catch(err => {
      this.log.error(err)
    })
  }

  /**
   * Tracks the incoming connection and check the connection limit
   */
  async _onConnect (evt: CustomEvent<Connection>): Promise<void> {
    const { detail: connection } = evt

    if (!this.started) {
      // This can happen when we are in the process of shutting down the node
      await connection.close()
      return
    }

    const peerId = connection.remotePeer
    const storedConns = this.connections.get(peerId)
    let isNewPeer = false

    if (storedConns != null) {
      storedConns.push(connection)
    } else {
      isNewPeer = true
      this.connections.set(peerId, [connection])
    }

    // only need to store RSA public keys, all other types are embedded in the peer id
    if (peerId.publicKey != null && peerId.type === 'RSA') {
      await this.peerStore.patch(peerId, {
        publicKey: peerId.publicKey
      })
    }

    if (isNewPeer) {
      this.events.safeDispatchEvent('peer:connect', { detail: connection.remotePeer })
    }
  }

  /**
   * Removes the connection from tracking
   */
  onDisconnect (evt: CustomEvent<Connection>): void {
    const { detail: connection } = evt

    if (!this.started) {
      // This can happen when we are in the process of shutting down the node
      return
    }

    const peerId = connection.remotePeer
    let storedConn = this.connections.get(peerId)

    if (storedConn != null && storedConn.length > 1) {
      storedConn = storedConn.filter((conn) => conn.id !== connection.id)
      this.connections.set(peerId, storedConn)
    } else if (storedConn != null) {
      this.connections.delete(peerId)
      this.events.safeDispatchEvent('peer:disconnect', { detail: connection.remotePeer })
    }
  }

  getConnections (peerId?: PeerId): Connection[] {
    if (peerId != null) {
      return this.connections.get(peerId) ?? []
    }

    let conns: Connection[] = []

    for (const c of this.connections.values()) {
      conns = conns.concat(c)
    }

    return conns
  }

  getConnectionsMap (): PeerMap<Connection[]> {
    return this.connections
  }

  async openConnection (peerIdOrMultiaddr: PeerId | Multiaddr | Multiaddr[], options: OpenConnectionOptions = {}): Promise<Connection> {
    if (!this.isStarted()) {
      throw new CodeError('Not started', codes.ERR_NODE_NOT_STARTED)
    }

    options.signal?.throwIfAborted()

    const { peerId } = getPeerAddress(peerIdOrMultiaddr)

    if (peerId != null && options.force !== true) {
      this.log('dial %p', peerId)
      const existingConnection = this.getConnections(peerId)
        .find(conn => !conn.transient)

      if (existingConnection != null) {
        this.log('had an existing non-transient connection to %p', peerId)

        return existingConnection
      }
    }

    const connection = await this.dialQueue.dial(peerIdOrMultiaddr, {
      ...options,
      priority: options.priority ?? DEFAULT_DIAL_PRIORITY
    })
    let peerConnections = this.connections.get(connection.remotePeer)

    if (peerConnections == null) {
      peerConnections = []
      this.connections.set(connection.remotePeer, peerConnections)
    }

    // we get notified of connections via the Upgrader emitting "connection"
    // events, double check we aren't already tracking this connection before
    // storing it
    let trackedConnection = false

    for (const conn of peerConnections) {
      if (conn.id === connection.id) {
        trackedConnection = true
      }
    }

    if (!trackedConnection) {
      peerConnections.push(connection)
    }

    return connection
  }

  async closeConnections (peerId: PeerId, options: AbortOptions = {}): Promise<void> {
    const connections = this.connections.get(peerId) ?? []

    await Promise.all(
      connections.map(async connection => {
        try {
          await connection.close(options)
        } catch (err: any) {
          connection.abort(err)
        }
      })
    )
  }

  async acceptIncomingConnection (maConn: MultiaddrConnection): Promise<boolean> {
    // check deny list
    const denyConnection = this.deny.some(ma => {
      return maConn.remoteAddr.toString().startsWith(ma.toString())
    })

    if (denyConnection) {
      this.log('connection from %a refused - connection remote address was in deny list', maConn.remoteAddr)
      return false
    }

    // check allow list
    const allowConnection = this.allow.some(ma => {
      return maConn.remoteAddr.toString().startsWith(ma.toString())
    })

    if (allowConnection) {
      this.incomingPendingConnections++

      return true
    }

    // check pending connections
    if (this.incomingPendingConnections === this.maxIncomingPendingConnections) {
      this.log('connection from %a refused - incomingPendingConnections exceeded by host', maConn.remoteAddr)
      return false
    }

    if (maConn.remoteAddr.isThinWaistAddress()) {
      const host = maConn.remoteAddr.nodeAddress().address

      try {
        await this.inboundConnectionRateLimiter.consume(host, 1)
      } catch {
        this.log('connection from %a refused - inboundConnectionThreshold exceeded by host %s', maConn.remoteAddr, host)
        return false
      }
    }

    if (this.getConnections().length < this.maxConnections) {
      this.incomingPendingConnections++

      return true
    }

    this.log('connection from %a refused - maxConnections exceeded', maConn.remoteAddr)
    return false
  }

  afterUpgradeInbound (): void {
    this.incomingPendingConnections--
  }

  getDialQueue (): PendingDial[] {
    return this.dialQueue.pendingDials
  }
}
