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
      discard
      # stderr.writeLine("unsupported flag: " & paramStr(i))

  if flags.serverIpAddress == TransportAddress():
    raise newException(ValueError, "server-address is not set")

proc seededRng(): ref HmacDrbgContext =
  var seed: cint = 0
  var rng = (ref HmacDrbgContext)()
  hmacDrbgInit(rng[], addr sha256Vtable, cast[pointer](addr seed), sizeof(seed).uint)
  return rng

proc runServer(f: Flags) {.async.} =
  let endlessFut = newFuture[void]()
  var switch = SwitchBuilder
    .new()
    .withRng(seededRng())
    .withAddresses(@[MultiAddress.init(f.serverIpAddress).tryGet()])
    .withTcpTransport()
    # .withQuicTransport()
    .withYamux()
    .withNoise()
    .build()
  switch.mount(Perf.new())
  await switch.start()
  await endlessFut # Await forever, exit on interrupt

proc intermediateReport(p: PerfClient) {.async.} =
  while true:
    await sleepAsync(1000.milliseconds)
    let stats = p.stats
    if stats.isFinal: 
      return

    let resultFinal =
      %*{
        "type": "intermediary",
        "timeSeconds": stats.duration.nanoseconds.float / 1_000_000_000.0,
        "uploadBytes": stats.uploadBytes,
        "downloadBytes": stats.downloadBytes,
      }
    stdout.writeLine($resultFinal)

proc runClient(f: Flags) {.async.} =
  let switchBuilder = SwitchBuilder
    .new()
    .withRng(newRng())
    .withAddress(MultiAddress.init("/ip4/127.0.0.1/tcp/0").tryGet())
    .withYamux()
    .withNoise()
  let switch =
    case f.transport
    of "tcp":
      switchBuilder.withTcpTransport().build()
    # of "quic-v1": switchBuilder.withQuicTransport().build()
    else:
      raise newException(ValueError, "unsupported transport: " & f.transport)
  await switch.start()

  let conn = await switch.dial(
    PeerId.init(fixedPeerId).tryGet(),
    @[MultiAddress.init(f.serverIpAddress).tryGet()],
    PerfCodec,
  )
  var perfClient = PerfClient.new()
  let durFut = perfClient.perf(conn, f.uploadBytes, f.downloadBytes)
  asyncSpawn intermediateReport(perfClient)

  let dur = await durFut
  let resultFinal =
    %*{
      "type": "final",
      "timeSeconds": dur.nanoseconds.float / 1_000_000_000.0,
      "uploadBytes": f.uploadBytes,
      "downloadBytes": f.downloadBytes,
    }
  stdout.writeLine($resultFinal)

proc main() {.async.} =
  var flags = Flags()
  flags.initFlagsFromParams()
  # stderr.writeLine("using flags: " & $flags)

  if flags.runServer:
    # stderr.writeLine("running server")
    await runServer(flags)
  else:
    # stderr.writeLine("running client")
    await runClient(flags)

waitFor(main())
