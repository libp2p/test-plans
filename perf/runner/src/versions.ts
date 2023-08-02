export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "rust-libp2p-quinn" | "zig-libp2p" | "https" | "quic-go",
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "v0.52",
        implementation: "rust-libp2p",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "yamux-v0.12",
        implementation: "rust-libp2p",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "v0.1",
        implementation: "https",
        transportStacks: ["tcp"]
    }
]
