export type Version = {
    id: string,
    containerImageID: string,
    transportStacks: string[],
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        containerImageID: "8b57bf547f7aa65fec9e6baf764cc1f8be195ef53343c230271116be353889e6",
        transportStacks: ["tcp", "quic-v1"]
    },
]
