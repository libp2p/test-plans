import gov024 from "./go/v0.24/image.json"
import gov023 from "./go/v0.23/image.json"
import gov022 from "./go/v0.22/image.json"
import rustv049 from "./rust/v0.49/image.json"
import rustv050 from "./rust/v0.50/image.json"

export type Version = {
    id: string,
    containerImageID: string,
    transports: string[],
    secureChannels: string[],
    muxers: string[],
}

export const versions: Array<Version> = [
    {
        id: "rust-v0.49.0",
        containerImageID: rustv049.imageID,
        transports: ["tcp", "ws"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "rust-v0.50.0",
        containerImageID: rustv050.imageID,
        transports: ["ws", "tcp", "quic-v1"],
        secureChannels: ["noise"],
        muxers: ["mplex", "yamux"],
    },
    {
        id: "go-v0.24.0",
        containerImageID: gov024.imageID,
        transports: ["tcp", "ws", "quic", "quic-v1", "webtransport"],
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
]