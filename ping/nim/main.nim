import serialization, json_serialization
import libp2p, testground_sdk, libp2p/protocols/ping
import chronos
import sequtils

type
  PeerData = object
    id: string
    addrs: seq[string]

testground(client):
  let addresses = getInterfaces().filterIt(it.name == "eth1").mapIt(it.addresses)
  if addresses.len < 1 or addresses[0].len < 1:
    quit "Can't find local ip!"

  let
    maxLatency = client.param(int, "max_latency_ms")
    rng = libp2p.newRng()
    address = addresses[0][0].host
    switch = newStandardSwitch(addrs = MultiAddress.init(address).tryGet(), rng = rng)
    pingProtocol = Ping.new(rng = rng)

  switch.mount(pingProtocol)
  await switch.start()
  defer: await switch.stop()

  let peersTopic = client.subscribe("peers", PeerData)
  await client.publish("peers",
    PeerData(
      id: $switch.peerInfo.peerId,
      addrs: switch.peerInfo.addrs.mapIt($it)
    )
  )
  echo "Listening on ", switch.peerInfo.addrs

  var peersInfo: seq[PeerData]
  while peersInfo.len < client.testInstanceCount:
    peersInfo.add(await peersTopic.popFirst())

  for peerInfo in peersInfo:
    if peerInfo.id == $switch.peerInfo.peerId: break
    let
      peerId = PeerId.init(peerInfo.id).tryGet()
      addrs = peerInfo.addrs.mapIt(MultiAddress.init(it).tryGet())
    await switch.connect(peerId, addrs)

  discard await client.signalAndWait("connected", client.testInstanceCount)

  proc pingPeer(peer: PeerData, tag: string) {.async.} =
    if peer.id == $switch.peerInfo.peerId: return
    let
      stream = await switch.dial(PeerId.init(peer.id).tryGet(), PingCodec)
      rtt = await pingProtocol.ping(stream)
    await stream.close()
    client.recordMessage("ping result (" & tag & ") from peer " & peer.id & ": " & $rtt)

  var futs: seq[Future[void]]
  for peer in peersInfo: futs.add(pingPeer(peer, "initial"))
  await allFutures(futs)

  discard await client.signalAndWait("initial", client.testInstanceCount)

  for iter in 1 .. client.param(int, "iterations"):
    let
      latency = milliseconds(rng.rand(maxLatency))
      callbackState = "network-configured-" & $iter
    client.recordMessage("Iteration " & $iter & ", my latency: " & $latency)
    await client.updateNetworkParameter(
      NetworkConf(
        enable: true,
        network: "default",
        callback_state: callbackState,
        callback_target: some client.testInstanceCount,
        routing_policy: "accept_all",
        default: LinkShape(latency: int(latency.nanoseconds))
      )
    )
    await client.waitForBarrier(callbackState, client.testInstanceCount)

    for peer in peersInfo: futs.add(pingPeer(peer, "iteration-" & $iter))
    await allFutures(futs)

    discard await client.signalAndWait("done-" & $iter, client.testInstanceCount)
