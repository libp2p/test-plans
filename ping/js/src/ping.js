import { network } from '@testground/sdk'
import { createLibp2p } from 'libp2p'
import { webSockets } from '@libp2p/websockets'
import { noise } from '@chainsafe/libp2p-noise'

module.exports = async (runenv, client) => {
  // consume test parameters from the runtime environment.
  const maxLatencyMs = runenv.runParams.testInstanceParams['max_latency_ms']
  const iterations = runenv.runParams.testInstanceParams['iterations']

  runenv.recordMessage(`started test instance; params: secure_channel=${secureChannel}, max_latency_ms=${maxLatencyMs}, iterations=${iterations}`)

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
    connectionEncryption: [noise()]
  })

  // start the libp2p node
  runenv.recordMessage('starting libp2p node')
  await node.start()

  const listenAddrs = node.getMultiaddrs()
  runenv.recordMessage(`libp2p is listening on the following addresses: ${listenAddrs}`)

  // obtain our peers and publish our own address as well
  // ...fetch the other peers
  const peers = []
  const peerTopic = await client.subscribe('peers')
  for (const i = 0; i < runenv.testInstanceCount; i++) {
    peers.push(await peerTopic.wait.next())
  }
  peerTopic.cancel()
  // ...publish our own
  client.publish('peers', { id: node.peerId, addrs: listenAddrs })

  // connect all (other) peers
  await Promise.all(peers.forEach((peer) => {
    if (peer.id === node.peerId) {
      return Promise.resolve()
    }
    runenv.recordMessage(`dial peer ${peer.id}`)
    return node.dial(peer.id).then((conn) => {
      runenv.recordMessage(`connected to ${peer.id}: ${conn.id} (${conn.stat})`)
    })
  }))

  await client.signalEntry('connected')
  await client.barrier('connected', runenv.testInstanceCount)

  // ping all (other) peers
  await Promise.all(peers.forEach((peer) => {
    if (peer.id === node.peerId) {
      return Promise.resolve()
    }
    runenv.recordMessage(`dial peer ${peer.id}`)
    return node.ping(peer.id).then((rtt) => {
      runenv.recordMessage(`ping result (initial) from peer ${peer.id}: ${rtt}`)
    })
  }))

  await client.signalEntry('initial')
  await client.barrier('initial', runenv.testInstanceCount)

  // TODO: next ping tests
}
