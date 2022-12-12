import gov024 from "./go/v0.24/image.json"
import gov0241 from "./go/v0.24.1/image.json"

export type Version = {
    id: string,
    containerImageID: string,
    transports: string[],
    secureChannels: string[],
    muxers: string[],
}

export const versions: Array<Version> = [
    {
        id: "go-v0.24.0",
        containerImageID: gov024.imageID,
        transports: ["tcp"],
        secureChannels: ["tls", "noise"],
        muxers: ["yamux"],
    },
    {
        id: "go-v0.24.1",
        containerImageID: gov0241.imageID,
        transports: ["tcp"],
        secureChannels: ["tls", "noise"],
        muxers: ["yamux"],
    },
]