export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p",
    containerImageID: string,
    transportStacks: string[],
    serverAddress?: string,
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        implementation: "rust-libp2p",
        containerImageID: "mxinden/libp2p-perf@3078e6a9941952486afe4b417a318ce0c372b6e2ef1e296c85f7811c1f170b09",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "go-v0.27.0",
        implementation: "go-libp2p",
        containerImageID: "mxinden/libp2p-perf@0fb68df50eada9dd10058bd7b6da614f2a31148dc0343be8eb5c7920f7bb4eef",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "zig-libp2p-v0.0.1",
        implementation: "zig-libp2p",
        containerImageID: "marcop010/zig-libp2p-perf@sha256:26b174b4ba38b206e216328f6027293f98c1db1e063ec27121609f2e5b9f409a",
        transportStacks: ["quic-v1"],
        serverAddress: "/ip4/13.56.168.61/udp/35052/quic-v1/p2p/12D3KooWKa5rDq3YhVzvAnvRoCrXhkWpA1CRsfY2hrBt2QYzLWih"
    },
]
