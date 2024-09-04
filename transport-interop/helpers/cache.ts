const AWS_BUCKET = process.env.AWS_BUCKET;
const scriptDir = __dirname;

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import * as child_process from 'child_process';
import ignore, { Ignore } from 'ignore'

const root = path.join(scriptDir, '..')
const arch = child_process.execSync('docker info -f "{{.Architecture}}"').toString().trim();

enum Mode {
    LoadCache = 1,
    PushCache,
}
const modeStr = process.argv[2];
let mode: Mode
switch (modeStr) {
    case "push":
        mode = Mode.PushCache
        break
    case "load":
        mode = Mode.LoadCache
        break
    default:
        throw new Error(`Unknown mode: ${modeStr}`)
}

(async () => {
    for (const implFamily of fs.readdirSync(path.join(root, 'impl'))) {
        const ig = ignore()

        addGitignoreIfPresent(ig, path.join(root, ".gitignore"))
        addGitignoreIfPresent(ig, path.join(root, "..", ".gitignore"))

        const implFamilyDir = path.join(root, 'impl', implFamily)
        addGitignoreIfPresent(ig, path.join(implFamilyDir, ".gitignore"))

        for (const impl of fs.readdirSync(implFamilyDir)) {
            const implFolder = fs.realpathSync(path.join(implFamilyDir, impl));
            if (!fs.statSync(implFolder).isDirectory()) {
                continue
            }

            addGitignoreIfPresent(ig, path.join(implFolder, ".gitignore"))

            // Get all the files in the implFolder:
            let files = walkDir(implFolder)
            // Turn them into relative paths:
            files = files.map(f => f.replace(implFolder + "/", ""))
            // Ignore files that are in the .gitignore:
            files = files.filter(ig.createFilter())
            // Sort them to be deterministic
            files = files.sort()

            console.log(implFolder)
            console.log("Files:", files)

            // Turn them back into absolute paths:
            files = files.map(f => path.join(implFolder, f))
            const cacheKey = await hashFiles(files)
            console.log("Cache key:", cacheKey)

            if (mode == Mode.PushCache) {
                console.log("Pushing cache")
                try {
                    if (!AWS_BUCKET) {
                        throw new Error("AWS_BUCKET not set")
                    }
                    const res = await fetch(`https://s3.amazonaws.com/${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`, { method: "HEAD" })
                    if (res.ok) {
                        console.log("Cache already exists")
                    } else {
                        // Read image id from image.json
                        const imageID = JSON.parse(fs.readFileSync(path.join(implFolder, 'image.json')).toString()).imageID;
                        console.log(`Pushing cache for ${impl}: ${imageID}`)
                        child_process.execSync(`docker image save ${imageID} | gzip | aws s3 cp - s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`);
                    }
                } catch (e) {
                    console.log("Failed to push image cache:", e)
                }
            } else if (mode == Mode.LoadCache) {
                if (fs.existsSync(path.join(implFolder, 'image.json'))) {
                    console.log("Already built")
                    continue
                }
                console.log("Loading cache")
                let cacheHit = false
                try {
                    if (!AWS_BUCKET) {
                        throw new Error("AWS_BUCKET not set")
                    }
                    // Check if the cache exists
                    const res = await fetch(`https://s3.amazonaws.com/${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`, { method: "HEAD" })
                    if (res.ok) {
                        const dockerLoadedMsg = child_process.execSync(`curl https://s3.amazonaws.com/${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz  | docker image load`).toString();
                        const loadedImageId = dockerLoadedMsg.match(/Loaded image( ID)?: (.*)/)[2];
                        if (loadedImageId) {
                            console.log(`Cache hit for ${loadedImageId}`);
                            fs.writeFileSync(path.join(implFolder, 'image.json'), JSON.stringify({ imageID: loadedImageId }) + "\n");
                            cacheHit = true
                        }
                    } else {
                        console.log("Cache not found")
                    }
                } catch (e) {
                    console.log("Cache not found:", e)
                }

                if (cacheHit) {
                    console.log("Building any remaining things from image.json")
                    // We're building using -o image.json. This tells make to
                    // not bother building image.json or anything it depends on.
                    child_process.execSync(`make -o image.json`, { cwd: implFolder, stdio: 'inherit' })
                } else {
                    console.log("No cache, building from scratch")
                    child_process.execSync(`make`, { cwd: implFolder, stdio: "inherit" })
                }
            }
        }
    }
})()

function walkDir(dir: string) {
    let results = [];
    fs.readdirSync(dir).forEach(f => {
        let dirPath = path.join(dir, f);
        let isDirectory = fs.statSync(dirPath).isDirectory();
        results = isDirectory ? results.concat(walkDir(dirPath)) : results.concat(path.join(dir, f));
    });
    return results;
};

async function hashFiles(files: string[]): Promise<string> {
    const fileHashes = await Promise.all(
        files.map(async (file) => {
            const data = await fs.promises.readFile(file);
            return crypto.createHash('sha256').update(data).digest('hex');
        })
    );
    return crypto.createHash('sha256').update(fileHashes.join('')).digest('hex');
}

function addGitignoreIfPresent(ig: Ignore, pathStr: string): boolean {
    try {
        if (fs.statSync(pathStr).isFile()) {
            ig.add(fs.readFileSync(pathStr).toString())
        }
        return true
    } catch {
        return false
    }
}
