export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p" | "https",
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "v0.51",
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
    // {
    //     id: "zig-libp2p-v0.0.1",
    //     implementation: "zig-libp2p",
    //     transportStacks: ["quic-v1"],
    // },
]