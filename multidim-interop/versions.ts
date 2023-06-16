import gov028 from "./impl/go/v0.28/image.json"
import gov027 from "./impl/go/v0.27/image.json"
import gov026 from "./impl/go/v0.26/image.json"
import gov025 from "./impl/go/v0.25/image.json"
import gov024 from "./impl/go/v0.24/image.json"
import gov023 from "./impl/go/v0.23/image.json"
import gov022 from "./impl/go/v0.22/image.json"
import rustv048 from "./impl/rust/v0.48/image.json"
import rustv049 from "./impl/rust/v0.49/image.json"
import rustv050 from "./impl/rust/v0.50/image.json"
import rustv051 from "./impl/rust/v0.51/image.json"
import jsV041 from "./impl/js/v0.41/node-image.json"
import jsV042 from "./impl/js/v0.42/node-image.json"
import jsV044 from "./impl/js/v0.44/node-image.json"
import jsV045 from "./impl/js/v0.45/image.json"
import nimv10 from "./impl/nim/v1.0/image.json"
import chromiumJsV041 from "./impl/js/v0.41/chromium-image.json"
import chromiumJsV042 from "./impl/js/v0.42/chromium-image.json"
import chromiumJsV044 from "./impl/js/v0.44/chromium-image.json"
import chromiumJsV045 from "./impl/js/v0.45/chromium-image.json"
import firefoxJsV045 from "./impl/js/v0.45/firefox-image.json"
import zigv001 from "./impl/zig/v0.0.1/image.json"
import javav001 from "./impl/java/v0.0.1/image.json"

export type Version = {
    id: string,
    containerImageID: string,
    // If defined, this will increase the timeout for tests using this version
    timeoutSecs?: number,
    transports: Array<(string | { name: string, onlyDial: boolean })>,
    secureChannels: string[],
    muxers: string[]
}

export const versions: Array<Version> = [
    {
        id: "rust-v0.48.0",
        containerImageID: rustv048.imageID,
        transports: ["ws", "tcp"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "rust-v0.49.0",
        containerImageID: rustv049.imageID,
        transports: ["ws", "tcp"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "rust-v0.50.0",
        containerImageID: rustv050.imageID,
        transports: ["ws", "tcp", "quic-v1"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "rust-v0.51.0",
        containerImageID: rustv051.imageID,
        transports: ["ws", "tcp", "quic-v1", "webrtc-direct"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "js-v0.41.0",
        containerImageID: jsV041.imageID,
        transports: ["tcp", "ws"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "js-v0.42.0",
        containerImageID: jsV042.imageID,
        transports: ["tcp", "ws", { name: "wss", onlyDial: true }],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "js-v0.44.0",
        containerImageID: jsV044.imageID,
        transports: ["tcp", "ws", { name: "wss", onlyDial: true }],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "js-v0.45.0",
        containerImageID: jsV045.imageID,
        transports: ["tcp", "ws", { name: "wss", onlyDial: true }],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "chromium-js-v0.41.0",
        containerImageID: chromiumJsV041.imageID,
        transports: [{ name: "webtransport", onlyDial: true }],
        secureChannels: [],
        muxers: []
    },
    {
        id: "chromium-js-v0.42.0",
        containerImageID: chromiumJsV042.imageID,
        transports: [{ name: "webtransport", onlyDial: true }, { name: "wss", onlyDial: true }],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"]
    },
    {
        id: "chromium-js-v0.44.0",
        containerImageID: chromiumJsV044.imageID,
        transports: [{ name: "webtransport", onlyDial: true }, { name: "wss", onlyDial: true }, { name: "webrtc-direct", onlyDial: true }],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "chromium-js-v0.45.0",
        containerImageID: chromiumJsV045.imageID,
        transports: [{ name: "webtransport", onlyDial: true }, { name: "wss", onlyDial: true }, { name: "webrtc-direct", onlyDial: true }, "webrtc"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "firefox-js-v0.45.0",
        containerImageID: firefoxJsV045.imageID,
        transports: [{ name: "wss", onlyDial: true }, { name: "webrtc-direct", onlyDial: true }, "webrtc"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.28.0",
        containerImageID: gov028.imageID,
        transports: ["tcp", "ws", "quic", "quic-v1", "webtransport"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.27.6",
        containerImageID: gov027.imageID,
        transports: ["tcp", "ws", "quic", "quic-v1", "webtransport"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.26.4",
        containerImageID: gov026.imageID,
        transports: ["tcp", "ws", "quic", "quic-v1", "webtransport"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.25.1",
        containerImageID: gov025.imageID,
        transports: ["tcp", "ws", "quic", "quic-v1", "webtransport"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.24.2",
        containerImageID: gov024.imageID,
        transports: ["tcp", "ws", "quic", "quic-v1", "webtransport", "wss"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.23.4",
        containerImageID: gov023.imageID,
        transports: ["tcp", "ws", "quic"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.22.0",
        containerImageID: gov022.imageID,
        transports: ["tcp", "ws", "quic"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "nim-v1.0",
        containerImageID: nimv10.imageID,
        transports: ["tcp", "ws"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "zig-v0.0.1",
        containerImageID: zigv001.imageID,
        transports: ["quic-v1"],
        secureChannels: [],
        muxers: [],
    },
    {
        id: "java-v0.0.1",
        containerImageID: javav001.imageID,
        transports: ["tcp"],
        secureChannels: ["tls", "noise"],
        muxers: ["mplex", "yamux"],
    },    
]
