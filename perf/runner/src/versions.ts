export type Version = {
    id: string,
    containerImageID: string,
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        containerImageID: "f567b27347a8d222e88f3c0b160e0547023e88aa700dc5e4255d9fcdf3d08eb1",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "go-master",
        containerImageID: "0fb68df50eada9dd10058bd7b6da614f2a31148dc0343be8eb5c7920f7bb4eef",
        transportStacks: ["tcp", "quic-v1"]
    },
]
