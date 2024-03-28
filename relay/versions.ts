import rustv051 from "./rust/v0.51/image.json"

export type Version = {
    id: string,
    containerImageID: string,
    // If defined, this will increase the timeout for tests using this version
    timeoutSecs?: number,
    roles: string[]
}

export const versions: Array<Version> = [
    {
        id: "rust-v0.51.0",
        containerImageID: rustv051.imageID,
        roles: ["source", "relay", "destination"],
    },
]
