const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const child_process = require('child_process');
const ignore = require('ignore');

const scriptDir = __dirname;
const root = path.join(scriptDir, '..');
const LOCAL_CACHE_DIR = process.env.LOCAL_CACHE_DIR || path.join(os.homedir(), '.cache/libp2p-interop-cache');
const arch = child_process.execSync('docker info -f "{{.Architecture}}"').toString().trim();

// Constants for mode
const Mode = {
    LoadCache: 1,
    PushCache: 2
};

const modeStr = process.argv[2];
let mode;
switch (modeStr) {
    case "push":
        mode = Mode.PushCache;
        break;
    case "load":
        mode = Mode.LoadCache;
        break;
    default:
        throw new Error(`Unknown mode: ${modeStr}`);
}

function walkDir(dir) {
    let results = [];
    fs.readdirSync(dir).forEach(f => {
        let dirPath = path.join(dir, f);
        let isDirectory = fs.statSync(dirPath).isDirectory();
        results = isDirectory ? results.concat(walkDir(dirPath)) : results.concat(path.join(dir, f));
    });
    return results;
}

async function hashFiles(files) {
    const fileHashes = await Promise.all(
        files.map(async (file) => {
            const data = await fs.promises.readFile(file);
            return crypto.createHash('sha256').update(data).digest('hex');
        })
    );
    return crypto.createHash('sha256').update(fileHashes.join('')).digest('hex');
}

function addGitignoreIfPresent(ig, pathStr) {
    try {
        if (fs.statSync(pathStr).isFile()) {
            ig.add(fs.readFileSync(pathStr).toString());
        }
        return true;
    } catch {
        return false;
    }
}

(async () => {
    // Ensure cache directory exists
    if (!fs.existsSync(LOCAL_CACHE_DIR)) {
        fs.mkdirSync(LOCAL_CACHE_DIR, { recursive: true });
    }

    for (const implFamily of fs.readdirSync(path.join(root, 'impl'))) {
        const ig = ignore.default();

        addGitignoreIfPresent(ig, path.join(root, ".gitignore"));
        addGitignoreIfPresent(ig, path.join(root, "..", ".gitignore"));

        const implFamilyDir = path.join(root, 'impl', implFamily);
        addGitignoreIfPresent(ig, path.join(implFamilyDir, ".gitignore"));

        for (const impl of fs.readdirSync(implFamilyDir)) {
            const implFolder = fs.realpathSync(path.join(implFamilyDir, impl));
            if (!fs.statSync(implFolder).isDirectory()) {
                continue;
            }

            addGitignoreIfPresent(ig, path.join(implFolder, ".gitignore"));

            // Get all the files in the implFolder:
            let files = walkDir(implFolder);
            // Turn them into relative paths:
            files = files.map(f => f.replace(implFolder + "/", ""));
            // Ignore files that are in the .gitignore:
            files = files.filter(ig.createFilter());
            // Sort them to be deterministic
            files = files.sort();

            console.log(implFolder);
            console.log("Files:", files);

            // Turn them back into absolute paths:
            files = files.map(f => path.join(implFolder, f));
            const cacheKey = await hashFiles(files);
            console.log("Cache key:", cacheKey);

            if (mode === Mode.PushCache) {
                console.log("Pushing to local cache");
                try {
                    // Check if image.json exists
                    if (fs.existsSync(path.join(implFolder, 'image.json'))) {
                        // Read image id from image.json
                        const imageID = JSON.parse(fs.readFileSync(path.join(implFolder, 'image.json')).toString()).imageID;
                        console.log(`Pushing cache for ${impl}: ${imageID}`);

                        const cacheFilePath = path.join(LOCAL_CACHE_DIR, `${cacheKey}-${arch}.tar.gz`);

                        // Skip if cache already exists
                        if (fs.existsSync(cacheFilePath)) {
                            console.log("Cache already exists");
                        } else {
                            // Save docker image to cache file
                            child_process.execSync(`docker image save ${imageID} | gzip > "${cacheFilePath}"`);
                            console.log(`Cached to ${cacheFilePath}`);
                        }
                    } else {
                        console.log("No image.json found, skipping cache");
                    }
                } catch (e) {
                    console.log("Failed to push to local cache:", e);
                }
            } else if (mode === Mode.LoadCache) {
                if (fs.existsSync(path.join(implFolder, 'image.json'))) {
                    console.log("Already built");
                    continue;
                }

                console.log("Loading from local cache");
                let cacheHit = false;

                try {
                    const cacheFilePath = path.join(LOCAL_CACHE_DIR, `${cacheKey}-${arch}.tar.gz`);

                    if (fs.existsSync(cacheFilePath)) {
                        console.log(`Found cache file: ${cacheFilePath}`);

                        // Load the image from cache
                        const dockerLoadedMsg = child_process.execSync(`docker image load -i "${cacheFilePath}"`).toString();
                        const loadedImageIdMatch = dockerLoadedMsg.match(/Loaded image( ID)?: (.*)/);

                        if (loadedImageIdMatch && loadedImageIdMatch[2]) {
                            const loadedImageId = loadedImageIdMatch[2];
                            console.log(`Cache hit for ${loadedImageId}`);
                            fs.writeFileSync(path.join(implFolder, 'image.json'), JSON.stringify({ imageID: loadedImageId }) + "\n");
                            cacheHit = true;
                        }
                    } else {
                        console.log("No cache file found");
                    }
                } catch (e) {
                    console.log("Failed to load from local cache:", e);
                }

                if (cacheHit) {
                    console.log("Building any remaining things from image.json");
                    // We're building using -o image.json. This tells make to
                    // not bother building image.json or anything it depends on.
                    child_process.execSync(`make -o image.json`, { cwd: implFolder, stdio: 'inherit' });
                } else {
                    console.log("No cache, building from scratch");
                    child_process.execSync(`make`, { cwd: implFolder, stdio: "inherit" });
                }
            }
        }
    }
})();
