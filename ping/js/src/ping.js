const { network } = require('@testground/sdk')
const { PingService } = require('libp2p')

function sleep (ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms)
  })
}

function getRandom (min, max) {
  return Math.random() * (max - min) + min
}

// Demonstrates synchronization between instances in the test group.
//
// In this example, the first instance to signal enrollment becomes the leader
// of the test case.
//
// The leader waits until all the followers have reached the state "ready"
// then, the followers wait for a signal from the leader to be released.
module.exports = async (runenv, client) => {
	// 📝  Consume test parameters from the runtime environment.
  const secureChannel = runenv.runParams.testInstanceParams['secure_channel']
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

	// ☎️  Let's construct the libp2p node.
	const listenAddr = `/ip4/${ip}/tcp/0`
	// host, err := compat.NewLibp2(ctx,
	// 	secureChannel,
	// 	libp2p.ListenAddrStrings(listenAddr),
	// )


	// 🚧  Now we instantiate the ping service.
	//
	// This adds a stream handler to our Host so it can process inbound pings,
	// and the returned PingService instance allows us to perform outbound pings.
  const ping = new PingService()
  // TODO: ^ how to construct this
}
