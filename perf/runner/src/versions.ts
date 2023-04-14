export type Version = {
    id: string,
    implementation: "go-libp2p" | "js-libp2p" | "nim-libp2p" | "rust-libp2p" | "zig-libp2p" | "go-https",
    containerImageID: string,
    transportStacks: string[],
    serverAddress?: string,
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        implementation: "rust-libp2p",
        containerImageID: "mxinden/libp2p-perf@sha256:80ef398de86fbb5be128c51de9900db908341d8ea0a77f9df935f449eb47696b",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "go-v0.27.0",
        implementation: "go-libp2p",
        containerImageID: "mxinden/libp2p-perf@sha256:0fb68df50eada9dd10058bd7b6da614f2a31148dc0343be8eb5c7920f7bb4eef",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "zig-libp2p-v0.0.1",
        implementation: "zig-libp2p",
        containerImageID: "marcop010/zig-libp2p-perf@sha256:26b174b4ba38b206e216328f6027293f98c1db1e063ec27121609f2e5b9f409a",
        transportStacks: ["quic-v1"],
        serverAddress: "/ip4/13.56.168.61/udp/35052/quic-v1/p2p/12D3KooWKa5rDq3YhVzvAnvRoCrXhkWpA1CRsfY2hrBt2QYzLWih"
    },
    {
        id: "go-https-v0.0.1",
        implementation: "go-https",
        containerImageID: "mxinden/libp2p-perf@sha256:ca9237cdbdfb13ac68f019bc1373ccfcc207798e461f8e9264d52f981d9d648c",
        transportStacks: ["tcp"]
    },
]
