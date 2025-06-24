mode = ScriptMode.Verbose

packageName = "nim-libp2p pref"
version = "1.10"
author = "Status Research & Development GmbH"
description = "LibP2P implementation"
license = "MIT"

requires "nim >= 2.2.0", "chronos >= 4.0.4", "bearssl >= 0.2.5"
# commit corresponds to v1.10.X (master branch) version of nim-libp2p
requires "libp2p#be1a2023ce41a4ccd298215f614820a8f3f0eb6e"
