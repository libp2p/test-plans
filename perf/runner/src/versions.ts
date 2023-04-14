export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p",
    containerImageID: string,
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        implementation: "rust-libp2p",
        containerImageID: "3078e6a9941952486afe4b417a318ce0c372b6e2ef1e296c85f7811c1f170b09",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "go-v0.27.0",
        implementation: "go-libp2p",
        containerImageID: "0fb68df50eada9dd10058bd7b6da614f2a31148dc0343be8eb5c7920f7bb4eef",
        transportStacks: ["tcp", "quic-v1"]
    },
]
