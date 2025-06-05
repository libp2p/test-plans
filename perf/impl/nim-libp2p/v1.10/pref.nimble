mode = ScriptMode.Verbose

packageName = "nim-libp2p pref"
version = "1.10"
author = "Status Research & Development GmbH"
description = "LibP2P implementation"
license = "MIT"

requires "nim >= 2.2.0",
  "nimcrypto >= 0.6.0 & < 0.7.0", "dnsclient >= 0.3.0 & < 0.4.0", "bearssl >= 0.2.5",
  "chronicles >= 0.10.3 & < 0.11.0", "chronos >= 4.0.4", "metrics", "secp256k1",
  "stew >= 0.4.0", "websock >= 0.2.0", "unittest2", "results", "quic >= 0.2.7"
