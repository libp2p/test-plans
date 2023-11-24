import { peerIdFromString } from '@libp2p/peer-id'
import { multiaddr } from '@multiformats/multiaddr'
import { debounce } from './utils.js'
import type { ComponentLogger, Libp2pEvents, Logger } from '@libp2p/interface'
import type { TypedEventTarget } from '@libp2p/interface/events'
import type { PeerId } from '@libp2p/interface/peer-id'
import type { PeerStore } from '@libp2p/interface/peer-store'
import type { TransportManager } from '@libp2p/interface-internal/transport-manager'
import type { Multiaddr } from '@multiformats/multiaddr'

export interface AddressManagerInit {
  /**
   * Pass an function in this field to override the list of addresses
   * that are announced to the network
   */
  announceFilter?: AddressFilter

  /**
   * list of multiaddrs string representation to listen
   */
  listen?: string[]

  /**
   * list of multiaddrs string representation to announce
   */
  announce?: string[]

  /**
   * list of multiaddrs string representation to never announce
   */
  noAnnounce?: string[]
}

export interface DefaultAddressManagerComponents {
  peerId: PeerId
  transportManager: TransportManager
  peerStore: PeerStore
  events: TypedEventTarget<Libp2pEvents>
  logger: ComponentLogger
}

/**
 * A function that takes a list of multiaddrs and returns a list
 * to announce
 */
export interface AddressFilter {
  (addrs: Multiaddr[]): Multiaddr[]
}

const defaultAddressFilter = (addrs: Multiaddr[]): Multiaddr[] => addrs

interface ObservedAddressMetadata {
  confident: boolean
}

/**
 * If the passed multiaddr contains the passed peer id, remove it
 */
function stripPeerId (ma: Multiaddr, peerId: PeerId): Multiaddr {
  const observedPeerIdStr = ma.getPeerId()

  // strip our peer id if it has been passed
  if (observedPeerIdStr != null) {
    const observedPeerId = peerIdFromString(observedPeerIdStr)

    // use same encoding for comparison
    if (observedPeerId.equals(peerId)) {
      ma = ma.decapsulate(multiaddr(`/p2p/${peerId.toString()}`))
    }
  }

  return ma
}

export class DefaultAddressManager {
  private readonly log: Logger
  private readonly components: DefaultAddressManagerComponents
  // this is an array to allow for duplicates, e.g. multiples of `/ip4/0.0.0.0/tcp/0`
  private readonly listen: string[]
  private readonly announce: Set<string>
  private readonly observed: Map<string, ObservedAddressMetadata>
  private readonly announceFilter: AddressFilter

  /**
   * Responsible for managing the peer addresses.
   * Peers can specify their listen and announce addresses.
   * The listen addresses will be used by the libp2p transports to listen for new connections,
   * while the announce addresses will be used for the peer addresses' to other peers in the network.
   */
  constructor (components: DefaultAddressManagerComponents, init: AddressManagerInit = {}) {
    const { listen = [], announce = [] } = init

    this.components = components
    this.log = components.logger.forComponent('libp2p:address-manager')
    this.listen = listen.map(ma => ma.toString())
    this.announce = new Set(announce.map(ma => ma.toString()))
    this.observed = new Map()
    this.announceFilter = init.announceFilter ?? defaultAddressFilter

    // this method gets called repeatedly on startup when transports start listening so
    // debounce it so we don't cause multiple self:peer:update events to be emitted
    this._updatePeerStoreAddresses = debounce(this._updatePeerStoreAddresses.bind(this), 1000)

    // update our stored addresses when new transports listen
    components.events.addEventListener('transport:listening', () => {
      this._updatePeerStoreAddresses()
    })
    // update our stored addresses when existing transports stop listening
    components.events.addEventListener('transport:close', () => {
      this._updatePeerStoreAddresses()
    })
  }

  _updatePeerStoreAddresses (): void {
    // if announce addresses have been configured, ensure they make it into our peer
    // record for things like identify
    const addrs = this.getAnnounceAddrs()
      .concat(this.components.transportManager.getAddrs())
      .concat(
        [...this.observed.entries()]
          .filter(([_, metadata]) => metadata.confident)
          .map(([str]) => multiaddr(str))
      ).map(ma => {
        // strip our peer id if it is present
        if (ma.getPeerId() === this.components.peerId.toString()) {
          return ma.decapsulate(`/p2p/${this.components.peerId.toString()}`)
        }

        return ma
      })

    this.components.peerStore.patch(this.components.peerId, {
      multiaddrs: addrs
    })
      .catch(err => { this.log.error('error updating addresses', err) })
  }

  /**
   * Get peer listen multiaddrs
   */
  getListenAddrs (): Multiaddr[] {
    return Array.from(this.listen).map((a) => multiaddr(a))
  }

  /**
   * Get peer announcing multiaddrs
   */
  getAnnounceAddrs (): Multiaddr[] {
    return Array.from(this.announce).map((a) => multiaddr(a))
  }

  /**
   * Get observed multiaddrs
   */
  getObservedAddrs (): Multiaddr[] {
    return Array.from(this.observed).map(([a]) => multiaddr(a))
  }

  /**
   * Add peer observed addresses
   */
  addObservedAddr (addr: Multiaddr): void {
    addr = stripPeerId(addr, this.components.peerId)
    const addrString = addr.toString()

    // do not trigger the change:addresses event if we already know about this address
    if (this.observed.has(addrString)) {
      return
    }

    this.observed.set(addrString, {
      confident: false
    })
  }

  confirmObservedAddr (addr: Multiaddr): void {
    addr = stripPeerId(addr, this.components.peerId)
    const addrString = addr.toString()

    const metadata = this.observed.get(addrString) ?? {
      confident: false
    }

    const startingConfidence = metadata.confident

    this.observed.set(addrString, {
      confident: true
    })

    // only trigger the 'self:peer:update' event if our confidence in an address has changed
    if (!startingConfidence) {
      this._updatePeerStoreAddresses()
    }
  }

  removeObservedAddr (addr: Multiaddr): void {
    addr = stripPeerId(addr, this.components.peerId)
    const addrString = addr.toString()

    this.observed.delete(addrString)
  }

  getAddresses (): Multiaddr[] {
    let addrs = this.getAnnounceAddrs().map(ma => ma.toString())

    if (addrs.length === 0) {
      // no configured announce addrs, add configured listen addresses
      addrs = this.components.transportManager.getAddrs().map(ma => ma.toString())
    }

    // add observed addresses we are confident in
    addrs = addrs.concat(
      Array.from(this.observed)
        .filter(([ma, metadata]) => metadata.confident)
        .map(([ma]) => ma)
    )

    // dedupe multiaddrs
    const addrSet = new Set(addrs)

    // Create advertising list
    return this.announceFilter(Array.from(addrSet)
      .map(str => multiaddr(str)))
      .map(ma => {
        // do not append our peer id to a path multiaddr as it will become invalid
        if (ma.protos().pop()?.path === true) {
          return ma
        }

        if (ma.getPeerId() === this.components.peerId.toString()) {
          return ma
        }

        return ma.encapsulate(`/p2p/${this.components.peerId.toString()}`)
      })
  }
}
