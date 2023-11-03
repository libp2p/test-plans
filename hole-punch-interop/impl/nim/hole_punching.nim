import std/[os, options]
import redis
import chronos, metrics, chronicles
import libp2p/[builders,
                  switch,
                  observedaddrmanager,
                  services/hpservice,
                  services/autorelayservice,
                  protocols/connectivity/autonat/client as aclient,
                  protocols/connectivity/relay/relay,
                  protocols/connectivity/autonat/service]
import libp2p/protocols/connectivity/relay/client as rclient
import tests/stubs/autonatclientstub
import libp2p/protocols/ping

proc createSwitch(r: Relay = nil, hpService: Service = nil): Switch =
  let rng = newRng()
  var builder = SwitchBuilder.new()
    .withRng(rng)
    .withAddresses(@[ MultiAddress.init("/ip4/0.0.0.0/tcp/0").tryGet() ])
    .withObservedAddrManager(ObservedAddrManager.new(minCount = 1))
    .withTcpTransport()
    .withYamux()
    .withAutonat()
    .withNoise()

  if hpService != nil:
    builder = builder.withServices(@[hpService])

  if r != nil:
    builder = builder.withCircuitRelay(r)

  let s =  builder.build()
  s.mount(Ping.new(rng=rng))
  return s

proc main() {.async.} =
  let relayClient = RelayClient.new()
  let autoRelayService = AutoRelayService.new(1, relayClient, nil, newRng())
  let autonatClientStub = AutonatClientStub.new(expectedDials = 1)
  autonatClientStub.answer = NotReachable
  let autonatService = AutonatService.new(autonatClientStub, newRng(), maxQueueSize = 1)
  let hpservice = HPService.new(autonatService, autoRelayService)

  let switch = createSwitch(relayClient, hpservice)
  await switch.start()

  let
    isListener = getEnv("MODE") == "listen"
    redisClient = open("redis", 6379.Port)

  debug "Connected to redis"

  if isListener:
    let relayAddr =
      try:
        redisClient.bLPop(@["RELAY_TCP_ADDRESS"], 20)
      except Exception as e:
        raise newException(CatchableError, e.msg)
    debug "Got relay address"

    let relayMA = MultiAddress.init(relayAddr[1]).tryGet()
    let relayId = await switch.connect(relayMA)
    debug "Connected to relay", relayId

    await sleepAsync(20.seconds)
    let listenerPeerId = switch.peerInfo.peerId
    discard redisClient.rPush("LISTEN_CLIENT_PEER_ID", $listenerPeerId)
    debug "Pushed listener client peer id to redis", listenerPeerId
  else:
   let listenerId =
     try:
       redisClient.bLPop(@["LISTEN_CLIENT_PEER_ID"], 20)
     except Exception as e:
       raise newException(CatchableError, e.msg)
  # var i = 1
  # var flags = Flags(transport: "tcp")
  # while i < paramCount():
  #   case paramStr(i)
  #   of "--run-server": flags.runServer = true
  #   of "--server-ip-address":
  #     flags.serverIpAddress = initTAddress(paramStr(i + 1))
  #     i += 1
  #   of "--transport":
  #     flags.transport = paramStr(i + 1)
  #     i += 1
  #   of "--upload-bytes":
  #     flags.uploadBytes = parseUInt(paramStr(i + 1))
  #     i += 1
  #   of "--download-bytes":
  #     flags.downloadBytes = parseUInt(paramStr(i + 1))
  #     i += 1
  #   else: discard
  #   i += 1
  #
  # if flags.runServer:
  #   await runServer(flags.serverIpAddress)
  # else:
  #   await runClient(flags)
try:
  discard waitFor(main().withTimeout(2.minutes))
except Exception as e:
  error "Unexpected error", msg = e.msg
quit(1)