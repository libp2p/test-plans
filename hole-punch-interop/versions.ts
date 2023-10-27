import fs from "fs"

export type Version = {
    id: string,
    // This can be the image ID, or a function that takes the version ID and returns the image ID.
    // By default it uses the canonicalImageIDLookup.
    containerImageID?: string,
    transports: Array<"tcp" | "quic">,
}

export const versions: Array<Version> = [
    {
        id: "rust-master",
        transports: ["tcp", "quic"],
        containerImageID: readImageId("./impl/rust/master/image.json"),
    } as Version,
].map((v: Version) => (typeof v.containerImageID === "undefined" ? ({ ...v, containerImageID: readImageId(canonicalImagePath(v.id)) }) : v))

function readImageId(path: string): string {
    return JSON.parse(fs.readFileSync(path, "utf8")).imageID;
}

// Finds the `image.json` for the given version id.
//
// Expects the form of "<impl>-vX.Y.Z" or "<impl>vX.Y".
// The image id must be in the file "./impl/<impl>/vX.Y/image.json" or "./impl/<impl>/v0.0.Z/image.json".
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
