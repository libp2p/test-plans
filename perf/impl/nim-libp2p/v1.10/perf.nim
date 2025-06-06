import os, strutils, strformat, json
import chronos, bearssl/[rand, hash]
import ./nimlibp2p/libp2p
import
  ./nimlibp2p/libp2p/[protocols/perf/client, protocols/perf/server, protocols/perf/core]

const fixedPeerId = "12D3KooWPnQpbXGqzgESFrkaFh1xvCrB64ADnLQQRYfMhnbSuFHF"

type Flags = object
  runServer: bool
  serverIpAddress: TransportAddress
  transport: string
  uploadBytes: uint
  downloadBytes: uint

proc initFlagsFromParams(flags: var Flags) =
  for arg in commandLineParams():
    let parts = arg.split("=")
    let key = if parts.len >= 1: parts[0] else: ""
    let val = if parts.len >= 2: parts[1] else: ""

    case key
    of "--run-server":
      flags.runServer = val == "true"
    of "--server-address":
      flags.serverIpAddress = initTAddress(val)
    of "--transport":
      flags.transport = val
    of "--upload-bytes":
      flags.uploadBytes = parseUInt(val)
    of "--download-bytes":
      flags.downloadBytes = parseUInt(val)
    else:
      stderr.writeLine("unsupported flag: " & arg)
  
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
    .withMplex()
    .withNoise()
    .build()
  switch.mount(Perf.new())
  await switch.start()
  await endlessFut # Await forever, exit on interrupt

proc runClient(f: Flags) {.async.} =
  let switchBuilder = SwitchBuilder
    .new()
    .withRng(newRng())
    .withAddress(MultiAddress.init("/ip4/127.0.0.1/tcp/0").tryGet())
    .withMplex()
    .withNoise()
  let switch =
    case f.transport
    of "tcp":
      switchBuilder.withTcpTransport().build()
    # of "quic-v1": switchBuilder.withQuicTransport().build()
    else:
      raise newException(ValueError, "unsupported transport: " & f.transport)
  await switch.start()

  let startTime = Moment.now()
  let conn = await switch.dial(
    PeerId.init(fixedPeerId).tryGet(),
    @[MultiAddress.init(f.serverIpAddress).tryGet()],
    PerfCodec,
  )
  discard await PerfClient.perf(conn, f.uploadBytes, f.downloadBytes)

  let dur = Moment.now() - startTime
  let resultFinal =
    %*{
      "type": "final",
      "timeSeconds": dur.seconds,
      "uploadBytes": f.uploadBytes,
      "downloadBytes": f.downloadBytes,
    }
  echo $resultFinal

proc main() {.async.} =
  var flags = Flags()
  flags.initFlagsFromParams()
  stderr.writeLine("using flags: " & $flags)

  if flags.runServer:
    await runServer(flags)
  else:
    await runClient(flags)

waitFor(main())
