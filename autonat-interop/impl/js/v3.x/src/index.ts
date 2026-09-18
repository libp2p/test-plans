// AutoNAT v2 client for the test-plans interop suite. Runs as either the server
// (an AutoNAT v2 service that dials addresses back) or the client (connects to
// the server and reports the reachability verdict for its own address),
// orchestrated over redis.

import { quic } from '@chainsafe/libp2p-quic'
import { autoNATv2 } from '@libp2p/autonat-v2'
import { identify } from '@libp2p/identify'
import { noise } from '@libp2p/noise'
import { tcp } from '@libp2p/tcp'
import { yamux } from '@libp2p/yamux'
import { multiaddr } from '@multiformats/multiaddr'
import { createLibp2p } from 'libp2p'
import os from 'node:os'
import { createClient } from 'redis'
import type { AutoNATv2 } from '@libp2p/autonat-v2'
import type { Libp2p } from '@libp2p/interface'

// redisAddr is the fixed address of the orchestrating redis server.
const redisAddr = 'redis://redis:6379'

// serverAddrKey is the redis list the server pushes its dialable multiaddr to
// and the client pops it from.
const serverAddrKey = 'AUTONAT_SERVER_ADDR'

// testTimeoutMillis bounds the whole run. The compose runner tears the stack
// down at 60s, so the client exits first with a status it can attribute.
const testTimeoutMillis = 55_000

// listenPort is the fixed port the node binds and announces, so the announced
// address is known ahead of the AutoNAT dial-back.
const listenPort = 4001

const transportTCP = 'tcp'
const transportQUIC = 'quic'
const modeServer = 'server'
const modeClient = 'client'

type RedisClient = ReturnType<typeof createClient>

interface Result {
  reachable: boolean
  tested_addr: string
}

async function main (): Promise<void> {
  const transport = process.env.TRANSPORT
  if (transport !== transportTCP && transport !== transportQUIC) {
    throw new Error(`invalid TRANSPORT ${JSON.stringify(transport)}`)
  }
  const mode = process.env.MODE
  if (mode !== modeServer && mode !== modeClient) {
    throw new Error(`invalid MODE ${JSON.stringify(mode)}`)
  }

  // QUIC cells use the third-party @chainsafe/libp2p-quic transport, since
  // official js-libp2p does not provide one.

  const deadline = AbortSignal.timeout(testTimeoutMillis)

  const rdb = createClient({ url: redisAddr })
  rdb.on('error', () => {})
  await connectRedis(rdb, deadline)

  const node = await newNode(transport)
  log(`peer id: ${node.peerId.toString()}`)
  log(`listening on: ${node.getMultiaddrs().map(m => m.toString()).join(', ')}`)

  try {
    if (mode === modeServer) {
      await runServer(node, rdb, transport, deadline)
    } else {
      await runClient(node, rdb, deadline)
    }
  } finally {
    try {
      await node.stop()
    } catch {}
    try {
      await rdb.quit()
    } catch {}
  }
}

// runServer publishes its dialable address and then serves AutoNAT requests
// until the compose runner stops the container.
async function runServer (node: Libp2p, rdb: RedisClient, transport: string, deadline: AbortSignal): Promise<void> {
  const addr = dialableAddr(node, transport)

  await rdb.rPush(serverAddrKey, addr)
  log(`published server address to redis (key: ${serverAddrKey}): ${addr}`)

  await new Promise<void>((resolve) => {
    deadline.addEventListener('abort', () => { resolve() }, { once: true })
  })
}

// runClient connects to the server and waits for the AutoNAT service to report
// a reachability verdict for the client's own address.
async function runClient (node: Libp2p<{ autoNAT: AutoNATv2 }>, rdb: RedisClient, deadline: AbortSignal): Promise<void> {
  const value = await popValue(rdb, serverAddrKey, deadline)
  const serverAddr = multiaddr(value)
  log(`server multiaddr: ${serverAddr}`)

  const verdict = awaitVerdict(node.services.autoNAT, deadline)

  await node.dial(serverAddr, { signal: deadline })
  log(`connected to server ${serverAddr}`)

  const res = await verdict
  process.stdout.write(`${JSON.stringify(res)}\n`)

  if (!res.reachable) {
    throw new Error(`address ${res.tested_addr} reported not reachable`)
  }
}

// awaitVerdict resolves with the first reachability verdict the AutoNAT service
// emits for one of the node's own addresses.
async function awaitVerdict (autoNAT: AutoNATv2, deadline: AbortSignal): Promise<Result> {
  return new Promise<Result>((resolve, reject) => {
    const onReachable = (evt: CustomEvent<{ addr: { toString: () => string } }>): void => {
      cleanup()
      resolve({ reachable: true, tested_addr: evt.detail.addr.toString() })
    }
    const onUnreachable = (evt: CustomEvent<{ addr: { toString: () => string } }>): void => {
      cleanup()
      resolve({ reachable: false, tested_addr: evt.detail.addr.toString() })
    }
    const onAbort = (): void => {
      cleanup()
      reject(new Error('timed out waiting for a reachability verdict'))
    }
    const cleanup = (): void => {
      autoNAT.removeEventListener('address:reachable', onReachable as EventListener)
      autoNAT.removeEventListener('address:unreachable', onUnreachable as EventListener)
      deadline.removeEventListener('abort', onAbort)
    }

    autoNAT.addEventListener('address:reachable', onReachable as EventListener)
    autoNAT.addEventListener('address:unreachable', onUnreachable as EventListener)
    deadline.addEventListener('abort', onAbort, { once: true })
  })
}

function dialableAddr (node: Libp2p, transport: string): string {
  const ip = interfaceIP()
  const addr = transport === transportQUIC
    ? `/ip4/${ip}/udp/${listenPort}/quic-v1`
    : `/ip4/${ip}/tcp/${listenPort}`
  return `${addr}/p2p/${node.peerId.toString()}`
}

// interfaceIP returns the node's first non-loopback IPv4 interface address.
function interfaceIP (): string {
  for (const iface of Object.values(os.networkInterfaces())) {
    for (const addr of iface ?? []) {
      if (addr.family === 'IPv4' && !addr.internal) {
        return addr.address
      }
    }
  }
  throw new Error('no non-loopback IPv4 interface address')
}

async function newNode (transport: string): Promise<Libp2p<{ autoNAT: AutoNATv2 }>> {
  const listen = [transport === transportQUIC ? `/ip4/0.0.0.0/udp/${listenPort}/quic-v1` : `/ip4/0.0.0.0/tcp/${listenPort}`]

  const socketOpts = { noDelay: true, keepAlive: true }

  return createLibp2p({
    addresses: {
      listen
    },
    transports: [
      transport === transportQUIC ? quic() : tcp({ dialOpts: socketOpts, listenOpts: socketOpts })
    ],
    connectionEncrypters: [noise()],
    streamMuxers: [yamux()],
    connectionGater: {
      // Allow every dial, so the AutoNAT dial-back is not filtered by address.
      denyDialMultiaddr: async () => false
    },
    services: {
      identify: identify(),
      autoNAT: autoNATv2({ startupDelay: 1_000 })
    }
  })
}

async function connectRedis (rdb: RedisClient, deadline: AbortSignal): Promise<void> {
  while (true) {
    try {
      await rdb.connect()
      return
    } catch (err) {
      throwIfAborted(deadline, 'timed out waiting for redis')
      log(`connecting to redis: ${String(err)}`)
      await sleep(100)
    }
  }
}

async function popValue (rdb: RedisClient, key: string, deadline: AbortSignal): Promise<string> {
  while (true) {
    const res = await rdb.blPop(key, 1)
    if (res != null) {
      return res.element
    }
    throwIfAborted(deadline, `timed out waiting for redis key ${key}`)
  }
}

function throwIfAborted (signal: AbortSignal, message: string): void {
  if (signal.aborted) {
    throw new Error(message)
  }
}

async function sleep (millis: number): Promise<void> {
  await new Promise<void>((resolve) => setTimeout(resolve, millis))
}

// log writes a diagnostic line to stderr, keeping stdout for the result json.
function log (message: string): void {
  process.stderr.write(`autonat-client: ${message}\n`)
}

main().catch((err) => {
  log(`FAILED: ${err instanceof Error ? err.message : String(err)}`)
  process.exit(1)
})
