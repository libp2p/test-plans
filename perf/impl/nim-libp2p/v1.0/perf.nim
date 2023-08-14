import os, parseopt, strutils, strformat
import chronos, bearssl/rand, bearssl/hash
import ./nim-libp2p/libp2p,
       ./nim-libp2p/libp2p/protocols/perf/client,
       ./nim-libp2p/libp2p/protocols/perf/server,
       ./nim-libp2p/libp2p/protocols/perf/core

const fixedPeerId = "12D3KooWPnQpbXGqzgESFrkaFh1xvCrB64ADnLQQRYfMhnbSuFHF"

type
  Flags = object
    runServer: bool
    serverIpAddress: TransportAddress
    transport: string
    uploadBytes: uint
    downloadBytes: uint

proc seededRng(): ref HmacDrbgContext =
  var seed: cint = 0
  var rng = (ref HmacDrbgContext)()
  hmacDrbgInit(rng[], addr sha256Vtable, cast[pointer](addr seed), sizeof(seed).uint)
  return rng

proc runServer(address: TransportAddress) {.async.} =
  let endlessFut = newFuture[void]()
  var switch = SwitchBuilder.new()
    .withRng(seededRng())
    .withAddresses(@[ MultiAddress.init(address).tryGet() ])
    .withTcpTransport()
    # .withQuicTransport() TODO: Remove comment when quic transport is done
    .withMplex()
    .withNoise()
    .build()
  # switch.peerInfo.peerId = PeerId.init(fixedPeerId).tryGet()
  switch.mount(Perf.new())
  await switch.start()
  await endlessFut # Await forever, exit on interrupt

proc runClient(f: Flags) {.async.} =
  let switchBuilder = SwitchBuilder.new()
    .withRng(newRng())
    .withAddress(MultiAddress.init("/ip4/127.0.0.1/tcp/0").tryGet())
    .withMplex()
    .withNoise()
  let switch =
    case f.transport:
    of "tcp": switchBuilder.withTcpTransport().build()
    # TODO: Remove comment when quic transport is done
    # of "quic": switchBuilder.withQuicTransport().build()
    else: raise (ref Defect)()
  await switch.start()
  let start = Moment.now()
  let conn = await switch.dial(PeerId.init(fixedPeerId).tryGet(),
                               @[ MultiAddress.init(f.serverIpAddress).tryGet() ],
                               PerfCodec)
  var dur = Moment.now() - start
  dur = dur + (await PerfClient.perf(conn, f.uploadBytes, f.downloadBytes))
  let ns = dur.nanos
  let s = Second.nanos
  echo "{\"latency\": ", fmt"{ns div s}.{ns mod s:09}", "}"

proc main() {.async.} =
  var av: seq[string] = @[]
  for i in 1..paramCount():
    av.add(paramStr(i))

  var flags = Flags(transport: "tcp")
  for kind, key, val in getopt(av):
    if kind == cmdLongOption:
      case key
      of "run-server": flags.runServer = true
      of "server-ip-address": flags.serverIpAddress = initTAddress(val)
      of "transport": flags.transport = val
      of "upload-bytes": flags.uploadBytes = parseUInt(val)
      of "download-bytes": flags.downloadBytes = parseUInt(val)
      else: discard

  if flags.runServer:
    await runServer(flags.serverIpAddress)
  else:
    await runClient(flags)

waitFor(main())
