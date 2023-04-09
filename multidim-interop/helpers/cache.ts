const AWS_BUCKET = process.env.AWS_BUCKET || 'libp2p-by-tf-aws-bootstrap';
const scriptDir = __dirname;

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import * as child_process from 'child_process';
import ignore from 'ignore'

const arch = child_process.execSync('docker info -f "{{.Architecture}}"').toString().trim();

enum Mode {
    LoadCache = 1,
    PushCache,
}
const mode: Mode = process.argv[2] == "push" ? Mode.PushCache : Mode.LoadCache;


(async () => {
    for (const implFamily of fs.readdirSync(path.join(scriptDir, '..', 'impl'))) {
        const ig = ignore()
        ig.add(".DS_Store")

        if (fs.statSync(path.join(scriptDir, "..", ".gitignore")).isFile()) {
            ig.add(fs.readFileSync(path.join(scriptDir, "..", ".gitignore")).toString())
        }
        if (fs.statSync(path.join(scriptDir, "..", "..", ".gitignore")).isFile()) {
            ig.add(fs.readFileSync(path.join(scriptDir, "..", "..", ".gitignore")).toString())
        }

        const implFamilyDir = path.join(scriptDir, '..', 'impl', implFamily)
        try {
            if (fs.statSync(path.join(implFamilyDir, ".gitignore")).isFile()) {
                ig.add(fs.readFileSync(path.join(implFamilyDir, ".gitignore")).toString())
            }
        } catch { }

        for (const impl of fs.readdirSync(implFamilyDir)) {
            const implFolder = fs.realpathSync(path.join(implFamilyDir, impl));
            if (!fs.statSync(implFolder).isDirectory()) {
                continue
            }

            try {
                if (fs.statSync(path.join(implFolder, ".gitignore")).isFile()) {
                    ig.add(fs.readFileSync(path.join(implFolder, ".gitignore")).toString())
                }
            } catch { }

            // Get all the files in the implFolder:
            let files = walkDir(implFolder)
            files = files.map(f => f.replace(implFolder + "/", ""))
            // Ignore files that are in the .gitignore:
            files = files.filter(f => !ig.ignores(f))
            // Sort them to be deterministic
            files = files.sort()

            console.log(implFolder)
            console.log("Files:", files)

            files = files.map(f => path.join(implFolder, f))
            const cacheKey = await hashFiles(files)
            console.log("Cache key:", cacheKey)

            if (mode == Mode.PushCache) {
                console.log("Pushing cache")
                try {
                    // Read image id from image.json
                    const imageID = JSON.parse(fs.readFileSync(path.join(implFolder, 'image.json')).toString()).imageID;
                    console.log(`Pushing cache for ${impl}: ${imageID}`)
                    child_process.execSync(`docker image save ${imageID} | gzip | aws s3 cp - s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`);
                } catch (e) {
                    console.log("Failed to push image cache:", e)
                }
            } else {
                console.log("Loading cache")
                try {
                    // Check if the cache exists
                    const res = await fetch(`https://s3.amazonaws.com/${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`, { method: "HEAD" })
                    if (res.ok) {
                        const dockerLoadedMsg = child_process.execSync(`curl https://s3.amazonaws.com/${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz  | docker image load`).toString();
                        const loadedImageId = dockerLoadedMsg.match(/Loaded image( ID)?: (.*)/)[2];
                        if (loadedImageId) {
                            console.log(`Cache hit for ${loadedImageId}`);
                            fs.writeFileSync(path.join(implFolder, 'image.json'), JSON.stringify({ imageID: loadedImageId }) + "\n");
                        }
                    } else {
                        console.log("Cache not found")
                    }
                } catch (e) {
                    console.log("Cache not found:", e)
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
