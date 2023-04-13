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
        containerImageID: "90bd7031f56ef2311659ea79b6e980080063b83ddc6644e7ebd5dbea869a1119",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "go-v0.27.0",
        implementation: "go-libp2p",
        containerImageID: "0fb68df50eada9dd10058bd7b6da614f2a31148dc0343be8eb5c7920f7bb4eef",
        transportStacks: ["tcp", "quic-v1"]
    },
]
