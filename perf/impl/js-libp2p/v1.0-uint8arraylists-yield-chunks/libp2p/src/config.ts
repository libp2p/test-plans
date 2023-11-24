import { CodeError } from '@libp2p/interface/errors'
import { FaultTolerance } from '@libp2p/interface/transport'
import { defaultAddressSort } from '@libp2p/utils/address-sort'
import { dnsaddrResolver } from '@multiformats/multiaddr/resolvers'
import mergeOptions from 'merge-options'
import { codes, messages } from './errors.js'
import type { Libp2pInit } from './index.js'
import type { ServiceMap, RecursivePartial } from '@libp2p/interface'
import type { Multiaddr } from '@multiformats/multiaddr'

const DefaultConfig: Partial<Libp2pInit> = {
  addresses: {
    listen: [],
    announce: [],
    noAnnounce: [],
    announceFilter: (multiaddrs: Multiaddr[]) => multiaddrs
  },
  connectionManager: {
    resolvers: {
      dnsaddr: dnsaddrResolver
    },
    addressSorter: defaultAddressSort
  },
  transportManager: {
    faultTolerance: FaultTolerance.FATAL_ALL
  }
}

export function validateConfig <T extends ServiceMap = Record<string, unknown>> (opts: RecursivePartial<Libp2pInit<T>>): Libp2pInit<T> {
  const resultingOptions: Libp2pInit<T> = mergeOptions(DefaultConfig, opts)

  if (resultingOptions.transports == null || resultingOptions.transports.length < 1) {
    throw new CodeError(messages.ERR_TRANSPORTS_REQUIRED, codes.ERR_TRANSPORTS_REQUIRED)
  }

  if (resultingOptions.connectionProtector === null && globalThis.process?.env?.LIBP2P_FORCE_PNET != null) { // eslint-disable-line no-undef
    throw new CodeError(messages.ERR_PROTECTOR_REQUIRED, codes.ERR_PROTECTOR_REQUIRED)
  }

  return resultingOptions
}
