import
  std/[os, strutils],
  chronos, redis, serialization, json_serialization,
  libp2p, libp2p/protocols/ping, libp2p/transports/wstransport

type
  ResultJson = object
    handshakePlusOneRTTMillis: float
    pingRTTMilllis: float

let
  testTimeout =
    try: seconds(parseInt(getEnv("test_timeout_seconds")))
    except CatchableError: 3.minutes

proc main {.async.} =
  let
    transport = getEnv("transport")
    muxer = getEnv("muxer")
    secureChannel = getEnv("security")
    isDialer = getEnv("is_dialer") == "true"
    ip = getEnv("ip", "0.0.0.0")
    redisAddr = getEnv("redis_addr", "redis:6379").split(":")

    # using synchronous redis because async redis is based on
    # asyncdispatch instead of chronos
    redisClient = open(redisAddr[0], Port(parseInt(redisAddr[1])))

    switchBuilder = SwitchBuilder.new()

  case "transport":
    of "tcp":
      discard switchBuilder.withTcpTransport().withAddress(
        MultiAddress.init("/ip4/" & ip & "/tcp/0").tryGet()
      )
    of "ws":
      discard switchBuilder.withTransport(proc (upgr: Upgrade): Transport = WsTransport.new(upgr)).withAddress(
        MultiAddress.init("/ip4/" & ip & "/tcp/0/ws").tryGet()
      )
    else: doAssert false

  case secureChannel:
    of "noise": discard switchBuilder.withNoise()
    else: doAssert false

  case muxer:
    of "yamux": discard switchBuilder.withYamux()
    of "mplex": discard switchBuilder.withMplex()
    else: doAssert false

  let
    rng = libp2p.newRng()
    switch = switchBuilder.withRng(rng).build()
    pingProtocol = Ping.new(rng = rng)
  switch.mount(pingProtocol)
  await switch.start()
  defer: await switch.stop()

  if not isDialer:
    discard redisClient.rPush("listenerAddr", $switch.peerInfo.fullAddrs.tryGet()[0])
    await sleepAsync(100.hours) # will get cancelled
  else:
    let
      remoteAddr = MultiAddress.init(redisClient.bLPop(@["listenerAddr"], testTimeout.seconds.int)[1]).tryGet()
      dialingStart = Moment.now()
      remotePeerId = await switch.connect(remoteAddr)
      stream = await switch.dial(remotePeerId, PingCodec)
      pingDelay = await pingProtocol.ping(stream)
      totalDelay = Moment.now() - dialingStart
    await stream.close()

    echo Json.encode(
      ResultJson(
        handshakePlusOneRTTMillis: float(totalDelay.milliseconds),
        pingRTTMilllis: float(pingDelay.milliseconds)
      )
    )
    quit(0)

discard waitFor(main().withTimeout(testTimeout))
quit(1)