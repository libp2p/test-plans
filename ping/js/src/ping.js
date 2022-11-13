const { sync, network } = require('@testground/sdk')
const libp2p = require('libp2p')

module.exports = async (runenv, client) => {
  // 📝  Consume test parameters from the runtime environment.
	const secureChannel = runenv.testInstanceParams("secure_channel")
	const maxLatencyMs = runenv.testInstanceParams("max_latency_ms")
	const iterations = runenv.testInstanceParams("iterations")

	// We can record messages anytime
	runenv.recordMessage(`started test instance; params: secure_channel=${secureChannel}, max_latency_ms=${maxLatencyMs}, iterations=${iterations}`)

  const netclient = network.newClient(client, runenv)
  // 🐣  Wait until all instances in this test run have signalled.
  await netclient.waitNetworkInitialized()

	// 🐥  Now all instances are ready for action.
  const ip = netclient.getDataNetworkIP()

	const listenAddr = `/ip4/${ip}/tcp/0`
  libp2p.createLibp2p({
    peerId: secureChannel,
    addresses: {
      listen: [listenAddr],
    }
  })
}
