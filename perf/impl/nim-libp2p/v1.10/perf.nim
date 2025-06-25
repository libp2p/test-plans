import os, strutils, strformat, json
import chronos, bearssl/[rand, hash]
import libp2p
import libp2p/[protocols/perf/client, protocols/perf/server, protocols/perf/core]

const fixedPeerId = "12D3KooWPnQpbXGqzgESFrkaFh1xvCrB64ADnLQQRYfMhnbSuFHF"

type Flags = object
  runServer: bool
  serverIpAddress: TransportAddress
  transport: string
  uploadBytes: uint
  downloadBytes: uint

proc initFlagsFromParams(flags: var Flags) =
  var i = 0
  while i < paramCount():
    i += 1
    case paramStr(i)
    of "--run-server":
      flags.runServer = true
    of "--server-address":
      i += 1
      flags.serverIpAddress = initTAddress(paramStr(i))
    of "--transport":
      i += 1
      flags.transport = paramStr(i)
    of "--upload-bytes":
      i += 1
      flags.uploadBytes = parseUInt(paramStr(i))
    of "--download-bytes":
      i += 1
      flags.downloadBytes = parseUInt(paramStr(i))
    else:
      stderr.writeLine("unsupported flag: " & paramStr(i))

  if flags.serverIpAddress == TransportAddress():
    raise newException(ValueError, "server-address is not set")

proc seededRng(): ref HmacDrbgContext =
  var seed: cint = 0
  var rng = (ref HmacDrbgContext)()
  hmacDrbgInit(rng[], addr sha256Vtable, cast[pointer](addr seed), sizeof(seed).uint)
  return rng

proc makeSwitch(f: Flags): Switch =
  let addrs =
    if f.runServer:
      @[MultiAddress.init(f.serverIpAddress).tryGet()]
    else:
      @[MultiAddress.init("/ip4/127.0.0.1/tcp/0").tryGet()]

  let rng =
    if f.runServer:
      seededRng() # use fixed seed that will match fixedPeerId
    else:
      newRng() 

  return SwitchBuilder
    .new()
    .withRng(rng)
    .withAddresses(addrs)
    .withTcpTransport()
    .withYamux()
    .withNoise()
    .build()

proc runServer(f: Flags) {.async.} =
  var switch = makeSwitch(f)
  switch.mount(Perf.new())
  await switch.start()

  await newFuture[void]() # await forever, exit on interrupt

proc writeReport(p: PerfClient, done: Future[void]) {.async.} =
  proc writeStats(stats: Stats) =
    let result =
      %*{
        "type": if stats.isFinal: "final" else: "intermediary",
        "timeSeconds": stats.duration.nanoseconds.float / 1_000_000_000.0,
        "uploadBytes": stats.uploadBytes,
        "downloadBytes": stats.downloadBytes,
      }
    stdout.writeLine($result)

  var prevStats: Stats
  while true:
    await sleepAsync(1000.milliseconds)
    var stats = p.currentStats()
    if stats.isFinal:
      writeStats(stats)
      done.complete()
      return

    # intermediary stats report should be diff from last intermediary report
    let statsInitial = stats
    stats.duration -= prevStats.duration
    stats.uploadBytes -= prevStats.uploadBytes
    stats.downloadBytes -= prevStats.downloadBytes
    prevStats = statsInitial

    writeStats(stats)

proc runClient(f: Flags) {.async.} =
  let switch = makeSwitch(f)
  await switch.start()

  let conn = await switch.dial(
    PeerId.init(fixedPeerId).tryGet(),
    @[MultiAddress.init(f.serverIpAddress).tryGet()],
    PerfCodec,
  )
  var perfClient = PerfClient.new()
  var done = newFuture[void]("report done")
  discard perfClient.perf(conn, f.uploadBytes, f.downloadBytes)
  asyncSpawn writeReport(perfClient, done)

  await done # block until reporting finishes

proc main() {.async.} =
  var flags = Flags()
  flags.initFlagsFromParams()
  stderr.writeLine("using flags: " & $flags)

  if flags.runServer:
    stderr.writeLine("running server")
    await runServer(flags)
  else:
    stderr.writeLine("running client")
    await runClient(flags)

waitFor(main())
