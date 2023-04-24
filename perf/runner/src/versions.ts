import rustv051 from "../../impl/rust/v0.51/image.json"
import go027 from "../../impl/go/v0.27/image.json"
import https from "../../impl/https/image.json"

export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p" | "https",
    containerImageID: string,
    transportStacks: string[],
    serverAddress?: string,
}

export const versions: Array<Version> = [
    {
        id: "rust-v0.51",
        implementation: "rust-libp2p",
        containerImageID: rustv051.imageID,
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "https",
        implementation: "https",
        containerImageID: https.imageID,
        transportStacks: ["tcp"]
    },
    {
        id: "go-v0.27.0",
        implementation: "go-libp2p",
        containerImageID: go027.imageID,
        transportStacks: ["tcp", "quic-v1"]
    },
    // {
    //     id: "zig-libp2p-v0.0.1",
    //     implementation: "zig-libp2p",
    //     containerImageID: "marcop010/zig-libp2p-perf@sha256:6a9f11961092cbebef93a55f5160fdd8584b7a11957b37b70d513e0948164353",
    //     transportStacks: ["quic-v1"],
    //     // serverAddress: "/ip4/13.56.168.61/udp/35052/quic-v1/p2p/12D3KooWKa5rDq3YhVzvAnvRoCrXhkWpA1CRsfY2hrBt2QYzLWih"
    // },
]
