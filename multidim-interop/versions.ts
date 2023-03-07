import gov025 from "./go/v0.25/image.json"
import gov024 from "./go/v0.24/image.json"
import gov023 from "./go/v0.23/image.json"
import gov022 from "./go/v0.22/image.json"
import rustv048 from "./rust/v0.48/image.json"
import rustv049 from "./rust/v0.49/image.json"
import rustv050 from "./rust/v0.50/image.json"
import jsV041 from "./js/v0.41/node-image.json"
import jsV042 from "./js/v0.42/node-image.json"
import nimv10 from "./nim/v1.0/image.json"
import chromiumJsV041 from "./js/v0.41/chromium-image.json"
import chromiumJsV042 from "./js/v0.42/chromium-image.json"

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
        transports: ["ws", "tcp", "quic-v1", "webrtc"],
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
        id: "chromium-js-v0.41.0",
        containerImageID: chromiumJsV041.imageID,
        transports: [{ name: "webtransport", onlyDial: true }, { name: "webrtc", onlyDial: true }],
        secureChannels: [],
        muxers: []
    },
    {
        id: "chromium-js-v0.42.0",
        containerImageID: chromiumJsV042.imageID,
        transports: [{ name: "webtransport", onlyDial: true }, { name: "webrtc", onlyDial: true }, { name: "wss", onlyDial: true }],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"]
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
]
