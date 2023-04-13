export type Version = {
    id: string,
    containerImageID: string,
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        containerImageID: "90bd7031f56ef2311659ea79b6e980080063b83ddc6644e7ebd5dbea869a1119",
        transportStacks: ["tcp", "quic-v1"]
    },
    {
        id: "go-master",
        containerImageID: "0fb68df50eada9dd10058bd7b6da614f2a31148dc0343be8eb5c7920f7bb4eef",
        transportStacks: ["tcp", "quic-v1"]
    },
]
