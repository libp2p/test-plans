import fs from "fs"
import path from "path"
import * as crypto from "crypto"
import ignore, { Ignore } from "ignore"

export type Version = {
    id: string,
    // This can be the image ID, or a function that takes the version ID and returns the image ID.
    // By default it uses the canonicalImageIDLookup.
    // If set to a ghcr.io/... URL, the tag is derived from the cache key automatically.
    containerImageID?: string | ((id: string) => string),
    // If defined, this will increase the timeout for tests using this version
    timeoutSecs?: number,
    transports: Array<(string | { name: string, onlyDial: boolean })>,
    secureChannels: string[],
    muxers: string[]
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

// Loads the container image id for the given browser version id. Expects the
// form of "<browser>-<impl>-vX.Y.Z" or "<impl>vX.Y" and the image id to be in the file
// "./impl/<impl>/vX.Y/<browser>-image.json" or "./impl/<impl>/v0.0.Z/<browser>-image.json"
function browserImageIDLookup(id: string): string {
    const [browser, ...rest] = id.split("-")
    const parentDir = path.dirname(canonicalImagePath(rest.join("-")))

    // Read the image ID from the JSON file on the filesystem
    const imageIDJSON = fs.readFileSync(path.join(parentDir, `${browser}-image.json`), "utf8")
    const imageID = JSON.parse(imageIDJSON).imageID
    return imageID
}

// --- GHCR image support ---

const root = path.join(__dirname)

// Parses a GHCR image name like "go-v0.45" or "js-v1.x-chromium" into
// the implementation family and version folder name.
function parseGHCRImageName(imageName: string): { family: string, versionFolder: string } {
    // Find the first "-v" to split family from version
    const vIdx = imageName.indexOf("-v")
    if (vIdx === -1) {
        throw new Error(`Cannot parse GHCR image name "${imageName}": no "-v" found`)
    }
    const family = imageName.substring(0, vIdx)
    const rest = imageName.substring(vIdx + 1) // includes the "v"

    // Version folder name never contains hyphens; any trailing "-suffix" is
    // the browser/variant prefix (e.g. "v1.x-chromium" → version "v1.x")
    const match = rest.match(/^(v[\d.x]+)(?:-(.+))?$/)
    if (!match) {
        throw new Error(`Cannot parse version from GHCR image name "${imageName}": "${rest}" doesn't match expected pattern`)
    }
    return { family, versionFolder: match[1] }
}

function walkDirSync(dir: string): string[] {
    let results: string[] = [];
    for (const f of fs.readdirSync(dir)) {
        const dirPath = path.join(dir, f);
        if (fs.statSync(dirPath).isDirectory()) {
            results = results.concat(walkDirSync(dirPath));
        } else {
            results.push(dirPath);
        }
    }
    return results;
}

function addGitignoreIfPresent(ig: Ignore, filePath: string): void {
    try {
        if (fs.statSync(filePath).isFile()) {
            ig.add(fs.readFileSync(filePath, "utf8"))
        }
    } catch {
        // File doesn't exist, skip
    }
}

function hashFilesSync(files: string[]): string {
    const fileHashes = files.map((file) => {
        const data = fs.readFileSync(file);
        return crypto.createHash("sha256").update(data).digest("hex");
    });
    return crypto.createHash("sha256").update(fileHashes.join("")).digest("hex");
}

// Computes the cache key for an implementation folder, replicating the logic
// from helpers/cache.ts and .github/scripts/compute-cache-key.mjs.
function computeCacheKey(family: string, versionFolder: string): string {
    const implFamilyDir = path.join(root, "impl", family)
    const implFolder = fs.realpathSync(path.join(implFamilyDir, versionFolder))

    const ig = ignore()
    addGitignoreIfPresent(ig, path.join(root, ".gitignore"))
    addGitignoreIfPresent(ig, path.join(root, "..", ".gitignore"))
    addGitignoreIfPresent(ig, path.join(implFamilyDir, ".gitignore"))
    addGitignoreIfPresent(ig, path.join(implFolder, ".gitignore"))

    let files = walkDirSync(implFolder)
    files = files.map(f => f.replace(implFolder + "/", ""))
    files = files.filter(ig.createFilter())
    files.sort()
    files = files.map(f => path.join(implFolder, f))

    return hashFilesSync(files)
}

// Resolves a GHCR container image reference by computing the cache key tag.
// Input:  "ghcr.io/libp2p/test-plans/go-v0.45"
// Output: "ghcr.io/libp2p/test-plans/go-v0.45:<cache-key>"
function resolveGHCRImageID(containerImageID: string): string {
    // Extract the image name (last path component)
    const imageName = containerImageID.substring(containerImageID.lastIndexOf("/") + 1)
    const { family, versionFolder } = parseGHCRImageName(imageName)
    const cacheKey = computeCacheKey(family, versionFolder)
    return `${containerImageID}:${cacheKey}`
}

export const versions: Array<Version> = JSON.parse(fs.readFileSync(path.join(__dirname, 'versionsInput.json') , 'utf8')).map((v: Version) => {
    // GHCR image references get their tag derived from the cache key
    if (typeof v.containerImageID === "string" && v.containerImageID.startsWith("ghcr.io/")) {
        return { ...v, containerImageID: resolveGHCRImageID(v.containerImageID) }
    }

    switch(v.containerImageID) {
        case "browser":
            return { ...v, containerImageID: browserImageIDLookup }
        case "canonical":
        default:
            return { ...v, containerImageID: canonicalImageIDLookup }
    }
});
