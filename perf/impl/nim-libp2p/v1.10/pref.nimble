mode = ScriptMode.Verbose

packageName = "nim-libp2p pref"
version = "1.10"
author = "Status Research & Development GmbH"
description = "LibP2P implementation"
license = "MIT"

requires "nim >= 2.2.0", "chronos >= 4.0.4", "bearssl >= 0.2.5"
# commit corresponds to v1.10.X (master branch) version of nim-libp2p
requires "libp2p#848fdde0a863f35d8efc23893c4b243b8a9be34b"
