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
        containerImageID: "2406b0778d7655b7eac7c0b448b1bf008c2411b7f128e899d894dcc12abb98fd",
        transportStacks: ["tcp", "quic-v1"]
    },
]
