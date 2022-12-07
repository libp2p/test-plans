import type { IPv4, IPv6 } from 'ipaddr.js'
import type { Logger } from 'winston'

export interface RunParams {
  testBranch: string
  testCase: string
  testGroupId: string
  testGroupInstanceCount: number
  testInstanceCount: number
  testInstanceParams: Record<string, string>
  testInstanceRole: string
  testOutputsPath: string
  testPlan: string
  testRepo: string
  testRun: string
  testSidecar: boolean
  testStartTime: number
  testSubnet: [IPv4 | IPv6, number]
  testTag: string
  toJSON: () => Object
}

export interface SignalEmitter {
  signalEvent: (event: Object) => void
}

export interface Events {
  /** Records an informational message. */
  recordMessage: (message: string) => void
  /** Records that the calling instance started. */
  recordStart: () => void
  /** Records that the calling instance succeeded. */
  recordSuccess: () => void
  /** Records that the calling instance failed with the supplied error. */
  recordFailure: (err: Error) => void
  /** Records that the calling instance crashed with the supplied error. */
  recordCrash: (err: Error) => void
}

export interface RunEnv extends Events, RunParams {
  logger: Logger
  runParams: RunParams
  getSignalEmitter: () => SignalEmitter|null
  setSignalEmitter: (e: SignalEmitter) => void
}
