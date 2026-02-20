const AWS_BUCKET = process.env.AWS_BUCKET;
const scriptDir = __dirname;

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as child_process from 'child_process';
import ignore, { Ignore } from 'ignore'

const holePunchInteropDir = path.join(scriptDir, '..')
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
    for (const implFamily of fs.readdirSync(path.join(holePunchInteropDir, 'impl'))) {
        const ig = ignore()

        addGitignoreIfPresent(ig, path.join(holePunchInteropDir, ".gitignore"))
        addGitignoreIfPresent(ig, path.join(holePunchInteropDir, "..", ".gitignore"))

        const implFamilyDir = path.join(holePunchInteropDir, 'impl', implFamily)

        addGitignoreIfPresent(ig, path.join(implFamilyDir, ".gitignore"))

        for (const impl of fs.readdirSync(implFamilyDir)) {
            const implFolder = fs.realpathSync(path.join(implFamilyDir, impl));

            if (!fs.statSync(implFolder).isDirectory()) {
                continue;
            }

            await loadCacheOrBuild(implFolder, ig);
        }

        await loadCacheOrBuild("router", ig);
        await loadCacheOrBuild("rust-relay", ig);
    }
})()

async function loadCacheOrBuild(dir: string, ig: Ignore) {
    addGitignoreIfPresent(ig, path.join(dir, ".gitignore"))

    // Get all the files in the dir:
    let files = walkDir(dir)
    // Turn them into relative paths:
    files = files.map(f => f.replace(dir + "/", ""))
    // Ignore files that are in the .gitignore:
    files = files.filter(ig.createFilter())
    // Sort them to be deterministic
    files = files.sort()

    console.log(dir)
    console.log("Files:", files)

    // Turn them back into absolute paths:
    files = files.map(f => path.join(dir, f))
    const cacheKey = await hashFiles(files)
    console.log("Cache key:", cacheKey)

    if (mode == Mode.PushCache) {
        console.log("Pushing cache")
        try {
            if (!AWS_BUCKET) {
                throw new Error("AWS_BUCKET not set")
            }
            try {
                child_process.execSync(`aws s3 ls s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`)
                console.log("Cache already exists")
            } catch (e) {
                console.log("Cache doesn't exist", e)
                // Read image id from image.json
                const imageID = JSON.parse(fs.readFileSync(path.join(dir, 'image.json')).toString()).imageID;
                console.log(`Pushing cache for ${dir}: ${imageID}`)
                child_process.execSync(`docker image save ${imageID} | gzip | aws s3 cp - s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`);
            }
        } catch (e) {
            console.log("Failed to push image cache:", e)
        }
    } else if (mode == Mode.LoadCache) {
        if (fs.existsSync(path.join(dir, 'image.json'))) {
            console.log("Already built")
            return;
        }
        console.log("Loading cache")
        let cacheHit = false
        try {
            if (!AWS_BUCKET) {
                throw new Error("AWS_BUCKET not set")
            }
            const cachePath = fs.mkdtempSync(path.join(os.tmpdir(), 'cache'))
            const archivePath = path.join(cachePath, 'archive.tar.gz')
            const dockerLoadedMsg = child_process.execSync(`aws s3 cp s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz ${archivePath} && docker image load -i ${archivePath}`).toString();
            const loadedImageId = dockerLoadedMsg.match(/Loaded image( ID)?: (.*)/)[2];
            if (loadedImageId) {
                console.log(`Cache hit for ${loadedImageId}`);
                fs.writeFileSync(path.join(dir, 'image.json'), JSON.stringify({imageID: loadedImageId}) + "\n");
                cacheHit = true
            }
        } catch (e) {
            console.log("Cache not found:", e)
        }

        if (cacheHit) {
            console.log("Building any remaining things from image.json")
            // We're building using -o image.json. This tells make to
            // not bother building image.json or anything it depends on.
            child_process.execSync(`make -o image.json`, {cwd: dir, stdio: 'inherit'})
        } else {
            console.log("No cache, building from scratch")
            child_process.execSync(`make`, {cwd: dir, stdio: "inherit"})
        }
    }
}

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
