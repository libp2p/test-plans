import { CodeError } from '@libp2p/interface/errors'
import merge from 'it-merge'
import { pipe } from 'it-pipe'
import { codes, messages } from '../errors.js'
import {
  storeAddresses,
  uniquePeers,
  requirePeers
} from './utils.js'
import type { AbortOptions } from '@libp2p/interface'
import type { ContentRouting } from '@libp2p/interface/content-routing'
import type { PeerInfo } from '@libp2p/interface/peer-info'
import type { PeerStore } from '@libp2p/interface/peer-store'
import type { Startable } from '@libp2p/interface/startable'
import type { CID } from 'multiformats/cid'

export interface CompoundContentRoutingInit {
  routers: ContentRouting[]
}

export interface CompoundContentRoutingComponents {
  peerStore: PeerStore
}

export class CompoundContentRouting implements ContentRouting, Startable {
  private readonly routers: ContentRouting[]
  private started: boolean
  private readonly components: CompoundContentRoutingComponents

  constructor (components: CompoundContentRoutingComponents, init: CompoundContentRoutingInit) {
    this.routers = init.routers ?? []
    this.started = false
    this.components = components
  }

  isStarted (): boolean {
    return this.started
  }

  async start (): Promise<void> {
    this.started = true
  }

  async stop (): Promise<void> {
    this.started = false
  }

  /**
   * Iterates over all content routers in parallel to find providers of the given key
   */
  async * findProviders (key: CID, options: AbortOptions = {}): AsyncIterable<PeerInfo> {
    if (this.routers.length === 0) {
      throw new CodeError('No content routers available', codes.ERR_NO_ROUTERS_AVAILABLE)
    }

    yield * pipe(
      merge(
        ...this.routers.map(router => router.findProviders(key, options))
      ),
      (source) => storeAddresses(source, this.components.peerStore),
      (source) => uniquePeers(source),
      (source) => requirePeers(source)
    )
  }

  /**
   * Iterates over all content routers in parallel to notify it is
   * a provider of the given key
   */
  async provide (key: CID, options: AbortOptions = {}): Promise<void> {
    if (this.routers.length === 0) {
      throw new CodeError('No content routers available', codes.ERR_NO_ROUTERS_AVAILABLE)
    }

    await Promise.all(this.routers.map(async (router) => { await router.provide(key, options) }))
  }

  /**
   * Store the given key/value pair in the available content routings
   */
  async put (key: Uint8Array, value: Uint8Array, options?: AbortOptions): Promise<void> {
    if (!this.isStarted()) {
      throw new CodeError(messages.NOT_STARTED_YET, codes.DHT_NOT_STARTED)
    }

    await Promise.all(this.routers.map(async (router) => {
      await router.put(key, value, options)
    }))
  }

  /**
   * Get the value to the given key.
   * Times out after 1 minute by default.
   */
  async get (key: Uint8Array, options?: AbortOptions): Promise<Uint8Array> {
    if (!this.isStarted()) {
      throw new CodeError(messages.NOT_STARTED_YET, codes.DHT_NOT_STARTED)
    }

    return Promise.any(this.routers.map(async (router) => {
      return router.get(key, options)
    }))
  }
}
