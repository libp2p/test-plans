export type Version = {
    id: string,
    containerImageID: string,
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        containerImageID: "f75472c773218b4da229e8b83c498d67de70cf2c6d145a969ca31aea14b78962",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "go-master",
        containerImageID: "9eaea3b70d5895d92219df971008eb1e55b8de769d1195cc03e2d74b314d6eac",
        transportStacks: ["tcp", "quic-v1"]
    },
]
