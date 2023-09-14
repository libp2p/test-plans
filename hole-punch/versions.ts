import fs from "fs"

export type Version = {
    id: string,
    // This can be the image ID, or a function that takes the version ID and returns the image ID.
    // By default it uses the canonicalImageIDLookup.
    containerImageID?: string | ((id: string) => string),
    // If defined, this will increase the timeout for tests using this version
    timeoutSecs?: number, // TODO: Add timeout config to images
    transports: Array<string>,
}

function canonicalImagePath(id: string): string {
    // Split by implementation and version
    const [impl, version] = id.split("-v")
    // Drop the patch version
    const [major, minor, patch] = version.split(".")
    let versionFolder = `v${major}.${minor}`
    if (major === "0" && minor === "0") {
        // We're still in the 0.0.x phase, so we use the patch version
        versionFolder = `v0.0.${patch}`
    }
    // Read the image ID from the JSON file on the filesystem
    return `./impl/${impl}/${versionFolder}/image.json`
}

// Loads the container image id for the given version id. Expects the form of
// "<impl>-vX.Y.Z" or "<impl>vX.Y" and the image id to be in the file
// "./impl/<impl>/vX.Y/image.json" or "./impl/<impl>/v0.0.Z/image.json"
function canonicalImageIDLookup(id: string): string {
    const imageIDJSON = fs.readFileSync(canonicalImagePath(id), "utf8")
    const imageID = JSON.parse(imageIDJSON).imageID
    return imageID
}

export const versions: Array<Version> = [
    {
        id: "rust-v0.52",
        transports: ["tcp", "quic"],
    },
].map((v: Version) => (typeof v.containerImageID === "undefined" ? ({ ...v, containerImageID: canonicalImageIDLookup }) : v))
