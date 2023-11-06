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
import libp2p/utils/heartbeat

proc createSwitch(r: Relay = nil, hpService: Service = nil): Switch =
  let rng = newRng()
  var builder = SwitchBuilder.new()
    .withRng(rng)
    .withAddresses(@[ MultiAddress.init("/ip4/0.0.0.0/tcp/0").tryGet() ])
    .withObservedAddrManager(ObservedAddrManager.new(minCount = 1))
    .withTcpTransport({ServerFlags.TcpNoDelay})
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


proc ping(conn: Connection) {.async.} =
  let pingProtocol = Ping.new()
  heartbeat "Ping background proc", 30.seconds:
    discard await pingProtocol.ping(conn)

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

  let relayAddr =
    try:
      redisClient.bLPop(@["RELAY_TCP_ADDRESS"], 0)
    except Exception as e:
      raise newException(CatchableError, e.msg)
  let relayMA = MultiAddress.init(relayAddr[1]).tryGet()
  debug "Got relay address", relayMA

  if isListener:
    let relayId = await switch.connect(relayMA)
    debug "Connected to relay", relayId

    let conn = await switch.dial(relayId, @[relayMA], PingCodec)
    asyncSpawn conn.ping()

    while switch.peerInfo.addrs.len == 0:
      debug "Waiting for addresses"
      await sleepAsync(200.milliseconds)

    let listenerPeerId = switch.peerInfo.peerId
    discard redisClient.rPush("LISTEN_CLIENT_PEER_ID", $listenerPeerId)
    debug "Addresses", addrs = $(switch.peerInfo.addrs)
    debug "Pushed listener client peer id to redis", listenerPeerId
    await sleepAsync(2.minutes)
    await conn.close()
  else:
    let listenerId =
      try:
        PeerId.init(redisClient.bLPop(@["LISTEN_CLIENT_PEER_ID"], 0)[1]).tryGet()
      except Exception as e:
        raise newException(CatchableError, e.msg)
    debug "Got listener peer id", listenerId
    let listenerRelayAddrStr = $relayMA & "/p2p-circuit"
    debug "Listener relay address string", listenerRelayAddrStr
    let listenerRelayAddr = MultiAddress.init(listenerRelayAddrStr).tryGet()
    debug "Dialing listener relay address", listenerRelayAddr
    await switch.connect(listenerId, @[listenerRelayAddr])
    await sleepAsync(2.minutes)
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
  discard waitFor(main().withTimeout(4.minutes))
except Exception as e:
  error "Unexpected error", msg = e.msg
quit(1)