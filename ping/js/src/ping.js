import pkg from '@testground/sdk'
const { network } = pkg

import { createLibp2p } from 'libp2p'
import { webSockets } from '@libp2p/websockets'
import { mplex } from '@libp2p/mplex'
import { noise } from '@chainsafe/libp2p-noise'
import { multiaddr } from '@multiformats/multiaddr'

;export default async (runenv, client) => {
  // consume test parameters from the runtime environment.
  const maxLatencyMs = runenv.runParams.testInstanceParams['max_latency_ms']
  const iterations = runenv.runParams.testInstanceParams['iterations']

  runenv.recordMessage(`started test instance; params: max_latency_ms=${maxLatencyMs}, iterations=${iterations}`)

  // instantiate a network client; see 'Traffic shaping' in the docs.
  const netClient = network.newClient(client, runenv)
  runenv.recordMessage('waiting for network initialization')

  // wait for the network to initialize; this should be pretty fast.
  await netClient.waitNetworkInitialized()
  runenv.recordMessage('network initilization complete')

  // We need to listen on (and advertise) our data network IP address, so we
  // obtain it from the NetClient.
  const ip = netClient.getDataNetworkIP()

  // create our libp2p node without starting it
  const node = await createLibp2p({
    start: false,
    addresses: {
      listen: [`/ip4/${ip}/tcp/8000/ws`]
    },
    transports: [webSockets()],
    connectionEncryption: [noise()],
    // required or the ping step throws an error
    streamMuxers: [mplex()]
  })

  // start the libp2p node
  runenv.recordMessage('starting libp2p node')
  await node.start()

  const listenAddrs = node.getMultiaddrs()
  runenv.recordMessage(`libp2p is listening on the following addresses: ${listenAddrs}`)

  // obtain our peers and publish our own address as well
  // ...publish our own first
  client.publish('peers', { id: node.peerId, addrs: listenAddrs })
  runenv.recordMessage(`published our own (peer: ${node.peerId}) address: ${listenAddrs}`)
  // ...and then fetch the other peers
  const peers = []
  const peerTopic = await client.subscribe('peers')
  for (let i = 0; i < runenv.testInstanceCount; i++) {
    const result = await peerTopic.wait.next()
    runenv.recordMessage(`received peer: ${JSON.stringify(result.value)}`)
    peers.push(result.value)
  }
  peerTopic.cancel()
  runenv.recordMessage(`received ${peers.length} peers`)

  // connect all (other) peers
  runenv.recordMessage(`connecting to all ${peers.length} peers`)
  await Promise.all(peers.map((peer) => {
    if (peer.id == node.peerId) {
      return Promise.resolve()
    }
    runenv.recordMessage(`node ${node.peerId} dials peer ${peer.id}`)
    // TODO: make it possible to dial directly using `peer`
    // (might mean that we need to turn our json struct into an actual libp2p peer type,
    //  but that would still be an improvement over this peer.addrs[0] hack)
    return node.dial(multiaddr(peer.addrs[0])).then((conn) => {
      runenv.recordMessage(`connected to ${peer.id}: ${conn.id} (${JSON.stringify(conn.stat)})`)
    })
  }))

  runenv.recordMessage('signalEntry: connected')
  await client.signalEntry('connected')
  runenv.recordMessage(`wait for barrier (${runenv.testInstanceCount}): connected`)
  await client.barrier('connected', runenv.testInstanceCount)

  // ping all (other) peers
  runenv.recordMessage(`pinging to all ${peers.length} peers`)
  await Promise.all(peers.map((peer) => {
    if (peer.id == node.peerId) {
      return Promise.resolve()
    }
    runenv.recordMessage(`node ${node.peerId} pings peer ${peer.id}`)
    // TODO: make it possible to ping directly using `peer`
    // (might mean that we need to turn our json struct into an actual libp2p peer type,
    //  but that would still be an improvement over this peer.addrs[0] hack)
    return node.ping(multiaddr(peer.addrs[0])).then((rtt) => {
      runenv.recordMessage(`ping result (initial) from peer ${peer.id}: ${rtt}`)
    })
  }))

  runenv.recordMessage('signalEntry: initial')
  await client.signalEntry('initial')
  runenv.recordMessage(`wait for barrier (${runenv.testInstanceCount}): initial`)
  await client.barrier('initial', runenv.testInstanceCount)

  // TODO: next ping tests

  runenv.recordMessage('Bye!')
}
