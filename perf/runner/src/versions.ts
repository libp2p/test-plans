export type Version = {
    id: string,
    containerImageID: string,
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        containerImageID: "33cdc2e4fc37",
        transportStacks: ["tcp", "quic-v1"]
    },
]
