// Hole-punch client for the test-plans interop suite. Runs as either the dialer
// or the listener, orchestrated over redis.

import { quic } from '@chainsafe/libp2p-quic'
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { dcutr } from '@libp2p/dcutr'
import { identify } from '@libp2p/identify'
import { noise } from '@libp2p/noise'
import { ping } from '@libp2p/ping'
import { tcp } from '@libp2p/tcp'
import { yamux } from '@libp2p/yamux'
import { multiaddr } from '@multiformats/multiaddr'
import { createLibp2p } from 'libp2p'
import { createClient } from 'redis'
import type { Ping } from '@libp2p/ping'
import type { Connection, Libp2p } from '@libp2p/interface'
import type { Multiaddr } from '@multiformats/multiaddr'

// redisAddr is the fixed address of the orchestrating redis server.
const redisAddr = 'redis://redis:6379'

// listenClientPeerIDKey is the redis list the listener pushes its peer id to and
// the dialer pops it from.
const listenClientPeerIDKey = 'LISTEN_CLIENT_PEER_ID'

// testTimeoutMillis bounds the whole run. The compose runner tears the stack
// down at 60s, so the client exits first with a status it can attribute.
const testTimeoutMillis = 55_000

const transportTCP = 'tcp'
const transportQUIC = 'quic'
const modeListen = 'listen'
const modeDial = 'dial'

type RedisClient = ReturnType<typeof createClient>

async function main (): Promise<void> {
  const transport = process.env.TRANSPORT
  if (transport !== transportTCP && transport !== transportQUIC) {
    throw new Error(`invalid TRANSPORT ${JSON.stringify(transport)}`)
  }
  const mode = process.env.MODE
  if (mode !== modeListen && mode !== modeDial) {
    throw new Error(`invalid MODE ${JSON.stringify(mode)}`)
  }

  // QUIC cells use the third-party @chainsafe/libp2p-quic transport, since
  // official js-libp2p does not provide one. Every js cell is known-failing; see
  // the README for the per-transport failure paths.

  const deadline = AbortSignal.timeout(testTimeoutMillis)

  const rdb = createClient({ url: redisAddr })
  rdb.on('error', () => {})
  await connectRedis(rdb, deadline)

  const relayAddr = await popRelayAddr(rdb, transport, deadline)
  log(`relay multiaddr: ${relayAddr}`)
  const relayMaddr = multiaddr(relayAddr)

  const node = await newNode(mode, transport)
  log(`peer id: ${node.peerId.toString()}`)
  log(`listening on: ${node.getMultiaddrs().map(m => m.toString()).join(', ')}`)

  try {
    await node.dial(relayMaddr, { signal: deadline })
    log(`connected to relay ${relayMaddr}`)

    if (mode === modeDial) {
      await runDialer(node, rdb, relayMaddr, deadline)
    } else {
      await runListener(node, rdb, deadline)
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

// runListener reserves a slot on the relay, publishes its peer id and then
// serves until the compose runner stops the container.
async function runListener (node: Libp2p, rdb: RedisClient, deadline: AbortSignal): Promise<void> {
  await waitForReservation(node, deadline)

  await rdb.rPush(listenClientPeerIDKey, node.peerId.toString())
  log(`published peer id to redis (key: ${listenClientPeerIDKey})`)

  // The dialer exits first and the runner tears the stack down, so there is no
  // completion condition to wait on here.
  await new Promise<void>((resolve) => {
    deadline.addEventListener('abort', () => { resolve() }, { once: true })
  })
}

// runDialer connects to the listener through the relay, waits for DCUtR to
// upgrade the connection to a direct one and reports the round-trip time.
async function runDialer (node: Libp2p<{ ping: Ping }>, rdb: RedisClient, relayMaddr: Multiaddr, deadline: AbortSignal): Promise<void> {
  const listenerID = await popValue(rdb, listenClientPeerIDKey, deadline)
  log(`listener peer id: ${listenerID}`)

  const circuitAddr = multiaddr(`${relayMaddr.toString()}/p2p-circuit/p2p/${listenerID}`)
  log(`dialling listener through relay: ${circuitAddr}`)

  await node.dial(circuitAddr, { signal: deadline })
  log('relayed connection established')

  const direct = await waitForDirectConn(node, listenerID, deadline)
  log(`direct connection established over ${direct.remoteAddr}`)

  const rtt = await node.services.ping.ping(direct.remoteAddr, { signal: deadline })
  log(`ping over direct connection: ${rtt}ms`)

  process.stdout.write(`${JSON.stringify({ rtt_to_holepunched_peer_millis: Math.round(rtt) })}\n`)
}

// waitForReservation blocks until the relay has granted a circuit reservation,
// which shows up as a /p2p-circuit address on the node.
//
// The listener holds its peer id back until then, since the dialer starts the
// exchange as soon as the circuit opens.
async function waitForReservation (node: Libp2p, deadline: AbortSignal): Promise<void> {
  while (true) {
    if (node.getMultiaddrs().some(m => m.toString().includes('/p2p-circuit'))) {
      log('relay reservation acquired')
      return
    }
    throwIfAborted(deadline, 'timed out waiting for a relay reservation')
    await sleep(50)
  }
}

// waitForDirectConn blocks until a connection to the peer that does not run over
// the relay appears.
async function waitForDirectConn (node: Libp2p, peerID: string, deadline: AbortSignal): Promise<Connection> {
  while (true) {
    const direct = directConn(node, peerID)
    if (direct != null) {
      return direct
    }
    throwIfAborted(deadline, 'timed out waiting for a direct connection')
    await sleep(50)
  }
}

// directConn returns a connection to the peer that does not run over the relay.
//
// The circuit component in the remote address is definitive, where the limits
// field is not: a relay can grant an unlimited circuit, whose connection carries
// no limits while still running over the relay.
function directConn (node: Libp2p, peerID: string): Connection | undefined {
  return node.getConnections().find(conn =>
    conn.remotePeer.toString() === peerID && !conn.remoteAddr.toString().includes('/p2p-circuit'))
}

async function newNode (mode: string, transport: string): Promise<Libp2p<{ ping: Ping }>> {
  const listen = [transport === transportQUIC ? '/ip4/0.0.0.0/udp/0/quic-v1' : '/ip4/0.0.0.0/tcp/0']
  if (mode === modeListen) {
    // The listener is reached over the relay, so it listens for a circuit as
    // well as on its own address for the direct dial DCUtR opens.
    listen.push('/p2p-circuit')
  }

  const socketOpts = { noDelay: true, keepAlive: true }

  return createLibp2p({
    addresses: { listen },
    transports: [
      transport === transportQUIC ? quic() : tcp({ dialOpts: socketOpts, listenOpts: socketOpts }),
      circuitRelayTransport()
    ],
    connectionEncrypters: [noise()],
    streamMuxers: [yamux()],
    connectionGater: {
      // The internet network is pinned to routable space, but the peers reach
      // each other over it, so no dial is filtered out by address.
      denyDialMultiaddr: async () => false
    },
    services: {
      identify: identify(),
      ping: ping(),
      dcutr: dcutr()
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

// popRelayAddr blocks on the relay address list for the transport and returns
// the entry the relay pushed.
async function popRelayAddr (rdb: RedisClient, transport: string, deadline: AbortSignal): Promise<string> {
  const key = transport === transportTCP ? 'RELAY_TCP_ADDRESS' : 'RELAY_QUIC_ADDRESS'
  return popValue(rdb, key, deadline)
}

// popValue blocks on a redis list until an entry is available or the deadline
// passes.
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
  process.stderr.write(`hole-punch-client: ${message}\n`)
}

main().catch((err) => {
  log(`FAILED: ${err instanceof Error ? err.message : String(err)}`)
  process.exit(1)
})
