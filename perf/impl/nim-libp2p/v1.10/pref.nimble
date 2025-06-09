mode = ScriptMode.Verbose

packageName = "nim-libp2p pref"
version = "1.10"
author = "Status Research & Development GmbH"
description = "LibP2P implementation"
license = "MIT"

requires "nim >= 2.2.0", "chronos >= 4.0.4", "bearssl >= 0.2.5"
# commit corresponds to v1.10.2 (draft) version of nim-libp2p
requires "libp2p#aa138b3a6c0d80de30c5f5b38fd0ea739376d92c"
