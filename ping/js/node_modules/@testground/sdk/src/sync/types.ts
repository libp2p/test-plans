export interface Barrier {
  wait: Promise<void>
  cancel: () => void
}

export interface State {
  barrier: (state: string, target: number) => Promise<Barrier>
  signalEntry: (state: string) => Promise<number>
  signalEvent: (event: any) => void
}

export interface Subscribe {
  cancel: () => void
  wait: AsyncGenerator<any, void, unknown>
}

export interface Topic {
  publish: (topic: string, payload: any) => Promise<number>
  subscribe: (topic: string) => Promise<Subscribe>
}

export type StateAndTopic = State & Topic

export interface PublishSubscribe {
  seq: number
  sub: Subscribe
}

export interface Sugar {
  publishAndWait: (topic: string, payload: any, state: string, target: number) => Promise<number>
  publishSubscribe: (topic: string, payload: any) => Promise<PublishSubscribe>
  signalAndWait: (state: string, target: number) => Promise<number>
}

export interface SyncClient extends State, Topic, Sugar {
  close: () => void
}

export interface PublishRequest {
  topic: string
  payload: any
}

export interface PublishResponse {
  seq: number
}

export interface SubscribeRequest {
  topic: string
}

export interface BarrierRequest {
  state: string
  target: number
}

export interface SignalEntryRequest {
  state: string
}

export interface SignalEntryResponse {
  seq: number
}
export interface Request {
  id?: string
  isCancel?: boolean
  publish?: PublishRequest
  subscribe?: SubscribeRequest
  barrier?: BarrierRequest
  signal_entry?: SignalEntryRequest
}

export interface Response {
  id: string
  error: string
  publish: PublishResponse
  subscribe: string // JSON Encoded Response
  signal_entry: SignalEntryResponse
}

export interface ResponseIterator {
  cancel: () => void
  wait: AsyncGenerator<Response, void, unknown>
}

export interface Socket {
  close: () => void
  requestOnce: (req: Request) => Promise<Response>
  request: (req: Request) => ResponseIterator
}

export interface PubSub {
  publish: (topic: string, payload: any) => Promise<number>
  subscribe: (key: string) => Promise<Subscribe>
}
