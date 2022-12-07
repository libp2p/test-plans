export interface NetworkClient {
  getDataNetworkIP: () => string
  waitNetworkInitialized: () => Promise<void>
  configureNetwork: (config: Config) => Promise<void>
}

export interface LinkShape {
  latency: number
  jitter: number
  bandwith: number
  loss: number
  corrupt: number
  corruptCorr: number
  reorder: number
  reorderCorr: number
  duplicate: number
  duplicateCorr: number
}

export type RoutingPolicyType = 'allow_all' | 'deny_all'

export interface Config {
  network: string
  enable: boolean
  callbackState: string
  callbackTarget: number
  IPv4: string
  IPv6: string
  routingPolicy: RoutingPolicyType
  default: LinkShape
}
