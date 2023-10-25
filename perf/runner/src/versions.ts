export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p" | "https" | "quic-go",
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "v0.53",
        implementation: "rust-libp2p",
        transportStacks: ["tcp"]
    },
    {
        id: "yamux",
        implementation: "rust-libp2p",
        transportStacks: ["tcp"]
    },
]
