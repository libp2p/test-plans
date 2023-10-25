export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p" | "https" | "quic-go",
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "v0.34",
        implementation: "quic-go",
        transportStacks: ["quic-v1"]
    },
    {
        id: "v0.53",
        implementation: "rust-libp2p",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "v0.1",
        implementation: "https",
        transportStacks: ["tcp"]
    },
    {
        id: "v0.27",
        implementation: "go-libp2p",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "v0.28",
        implementation: "go-libp2p",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "v0.29",
        implementation: "go-libp2p",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "v0.31",
        implementation: "go-libp2p",
        transportStacks: ["tcp", "quic-v1"]
    },
    // {
    //     id: "v0.46",
    //     implementation: "js-libp2p",
    //     transportStacks: ["tcp"]
    // }
]
