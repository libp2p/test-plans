const AWS_BUCKET = process.env.AWS_BUCKET;
const CACHE_DIR = process.env.CACHE_DIR;
const scriptDir = __dirname;

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as child_process from 'child_process';
import ignore, { Ignore } from 'ignore'
import yargs from 'yargs/yargs';
import { Version, versions } from '../versions';
import { parseFilterArgs } from '../src/testFilter';

const root = path.join(scriptDir, '..')

enum Mode {
    LoadCache = 1,
    PushCache,
}

/**
 * Get the set of required implementation IDs based on test filters
 * This generates test names and extracts implementation IDs without needing image.json files
 */
async function getRequiredImplementations(
    nameFilter: string[] | null,
    nameIgnore: string[] | null,
    verbose: boolean,
    extraVersions: Array<Version>
): Promise<Set<string>> {
    const sqlite3 = await import('sqlite3');
    const { open } = await import('sqlite');
    const { matchesFilter } = await import('../src/testFilter');

    const allVersions = versions.concat(extraVersions);
    const filterOptions = { nameFilter, nameIgnore, verbose };

    // Use sqlite to generate test combinations (same logic as buildTestSpecs)
    const db = await open({
        filename: ":memory:",
        driver: sqlite3.default.Database,
    });

    await db.exec(`CREATE TABLE IF NOT EXISTS transports (id string not null, transport string not null, onlyDial boolean not null);`)
    await db.exec(`CREATE TABLE IF NOT EXISTS secureChannels (id string not null, sec string not null);`)
    await db.exec(`CREATE TABLE IF NOT EXISTS muxers (id string not null, muxer string not null);`)

    function normalizeTransport(transport: string | { name: string, onlyDial: boolean }): { name: string, onlyDial: boolean } {
        return typeof transport === "string" ? { name: transport, onlyDial: false } : transport
    }

    await Promise.all(
        allVersions.flatMap(version => {
            return [
                db.exec(`INSERT INTO transports (id, transport, onlyDial)
                VALUES ${version.transports.map(normalizeTransport).map(transport => `("${version.id}", "${transport.name}", ${transport.onlyDial})`).join(", ")};`),
                (version.secureChannels.length > 0 ?
                    db.exec(`INSERT INTO secureChannels (id, sec)
                VALUES ${version.secureChannels.map(sec => `("${version.id}", "${sec}")`).join(", ")};`) : []),
                (version.muxers.length > 0 ?
                    db.exec(`INSERT INTO muxers (id, muxer)
                VALUES ${version.muxers.map(muxer => `("${version.id}", "${muxer}")`).join(", ")};`) : []),
            ]
        })
    )

    const standaloneTransports = ["quic", "quic-v1", "webtransport", "webrtc", "webrtc-direct"].map(x => `"${x}"`).join(", ")
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport, ma.muxer, sa.sec
                     FROM transports a, transports b, muxers ma, muxers mb, secureChannels sa, secureChannels sb
                     WHERE a.id == ma.id
                     AND NOT b.onlyDial
                     AND b.id == mb.id
                     AND a.id == sa.id
                     AND b.id == sb.id
                     AND a.transport == b.transport
                     AND sa.sec == sb.sec
                     AND ma.muxer == mb.muxer
                     AND a.transport NOT IN (${standaloneTransports});`);
    const standaloneTransportsQueryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport
                     FROM transports a, transports b
                     WHERE a.transport == b.transport
                     AND NOT b.onlyDial
                     AND a.transport IN (${standaloneTransports});`);
    await db.close();

    // Extract implementation IDs from filtered test names
    const implIDs = new Set<string>();

    for (const test of queryResults) {
        const name = `${test.id1} x ${test.id2} (${test.transport}, ${test.sec}, ${test.muxer})`;
        if (matchesFilter(name, filterOptions)) {
            implIDs.add(test.id1);
            implIDs.add(test.id2);
        }
    }

    for (const test of standaloneTransportsQueryResults) {
        const name = `${test.id1} x ${test.id2} (${test.transport})`;
        if (matchesFilter(name, filterOptions)) {
            implIDs.add(test.id1);
            implIDs.add(test.id2);
        }
    }

    return implIDs;
}

/**
 * Map implementation ID to filesystem path
 * e.g., "rust-v0.53" -> { family: "rust", version: "v0.53", path: "impl/rust/v0.53" }
 */
function getImplPath(implID: string): { family: string, version: string, path: string } | null {
    // Parse implID like "rust-v0.53" or "chromium-rust-v0.53"
    // Need to handle both standard and browser variants
    const match = implID.match(/^(.+)-v(.+)$/);
    if (!match) {
        return null;
    }

    const family = match[1];
    const versionStr = match[2];
    const [major, minor, patch] = versionStr.split(".");

    // Determine version folder (matching logic from versions.ts)
    let versionFolder = `v${major}.${minor}`;
    if (major === "0" && minor === "0" && patch) {
        versionFolder = `v0.0.${patch}`;
    }

    // Build path
    const implPath = path.join(root, 'impl', family, versionFolder);

    return { family, version: versionFolder, path: implPath };
}

(async () => {
    // Parse command line arguments
    const argv = await yargs(process.argv.slice(2))
        .command('load', 'Load cached images and build missing ones')
        .command('push', 'Push built images to cache')
        .options({
            'name-filter': {
                description: 'Only cache images for tests including any of these names (pipe separated)',
                default: "",
                type: 'string'
            },
            'name-ignore': {
                description: 'Do not cache images for tests including any of these names (pipe separated)',
                default: "",
                type: 'string'
            },
            'extra-version': {
                description: 'Paths to JSON files for additional versions to include',
                default: [],
                type: 'array'
            },
            'verbose': {
                description: 'Enable verbose logging',
                default: false,
                type: 'boolean'
            }
        })
        .help()
        .alias('help', 'h')
        .argv;

    const modeStr = argv._[0] as string;
    let mode: Mode;
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

    const verbose = argv.verbose as boolean;

    // Parse filter arguments
    const { nameFilter, nameIgnore } = parseFilterArgs(
        argv['name-filter'] as string,
        argv['name-ignore'] as string,
        verbose
    );

    // Load extra versions
    const extraVersions: Array<Version> = [];
    for (let versionPath of (argv['extra-version'] as string[]).filter(p => p !== "")) {
        const contents = await fs.promises.readFile(versionPath);
        extraVersions.push(JSON.parse(contents.toString()));
    }

    // Get filtered implementation IDs
    const requiredImpls = await getRequiredImplementations(
        nameFilter,
        nameIgnore,
        verbose,
        extraVersions
    );

    if (verbose) {
        console.log("\n=== Required Implementations ===");
        Array.from(requiredImpls).sort().forEach(id => console.log(`  - ${id}`));
        console.log(`Total: ${requiredImpls.size}\n`);
    }

    // Build a map of all available implementations
    const allImpls = new Map<string, string>(); // implID → implPath
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

            // Derive implID from path (e.g., rust/v0.53 → rust-v0.53)
            const implID = `${implFamily}-${impl}`;
            allImpls.set(implID, implFolder);
        }
    }

    // Show ignored implementations in verbose mode
    if (verbose && requiredImpls.size > 0) {
        console.log("\n=== Ignored Implementations ===");
        const ignoredImpls = Array.from(allImpls.keys()).filter(id => !requiredImpls.has(id)).sort();
        if (ignoredImpls.length > 0) {
            ignoredImpls.forEach(id => console.log(`  - ${id}`));
        } else {
            console.log("  (none)");
        }
        console.log();
    }

    // If no filters provided, process all implementations
    // If filters were provided but matched nothing, show warning and exit
    const implsToProcess = (nameFilter || nameIgnore) ? requiredImpls : new Set(allImpls.keys());

    if (implsToProcess.size === 0) {
        console.warn("Warning: No implementations match the provided filters");
        return;
    }

    console.log(`Processing ${implsToProcess.size} implementation(s)\n`);

    // Get Docker architecture (only needed when actually processing images)
    let arch: string;
    try {
        arch = child_process.execSync('docker info -f "{{.Architecture}}"').toString().trim();
    } catch (e) {
        console.error("Error: Unable to connect to Docker.");
        console.error("Please ensure Docker is installed and running before using the cache command.");
        process.exit(1);
    }

    // Process only required implementations
    for (const implID of Array.from(implsToProcess)) {
        const implFolder = allImpls.get(implID);
        if (!implFolder) {
            console.warn(`Warning: Required implementation ${implID} not found`);
            continue;
        }

        if (verbose) {
            console.log(`\n>>> Processing: ${implID}`);
            console.log(`    Path: ${implFolder}`);
        } else {
            console.log(`\n>>> ${implID}`);
        }

        const ig = ignore();
        addGitignoreIfPresent(ig, path.join(root, ".gitignore"));
        addGitignoreIfPresent(ig, path.join(root, "..", ".gitignore"));

        const implFamilyDir = path.dirname(implFolder);
        addGitignoreIfPresent(ig, path.join(implFamilyDir, ".gitignore"));
        addGitignoreIfPresent(ig, path.join(implFolder, ".gitignore"));

        // Get all the files in the implFolder:
        let files = walkDir(implFolder);
        // Turn them into relative paths:
        files = files.map(f => f.replace(implFolder + "/", ""));
        // Ignore files that are in the .gitignore:
        files = files.filter(ig.createFilter());
        // Sort them to be deterministic
        files = files.sort();

        if (verbose) {
            console.log(`    Files (${files.length}):`, files.slice(0, 5).join(", ") + (files.length > 5 ? "..." : ""));
        }

        // Turn them back into absolute paths:
        files = files.map(f => path.join(implFolder, f));
        const cacheKey = await hashFiles(files);

        if (verbose) {
            console.log(`    Cache key: ${cacheKey}`);
        }

        if (mode == Mode.PushCache) {
            if (verbose) {
                console.log("    Checking if cache exists...");
            }
            try {
                // Use local cache if CACHE_DIR is set, otherwise fall back to AWS S3
                if (CACHE_DIR) {
                    const cacheFile = path.join(CACHE_DIR, 'imageCache', `${cacheKey}-${arch}.tar.gz`)
                    if (fs.existsSync(cacheFile)) {
                        console.log("  ✓ Cache already exists");
                    } else {
                        console.log("  ⊕ Creating cache entry");
                        // Ensure the imageCache directory exists
                        fs.mkdirSync(path.join(CACHE_DIR, 'imageCache'), { recursive: true })
                        // Read image id from image.json
                        const imageID = JSON.parse(fs.readFileSync(path.join(implFolder, 'image.json')).toString()).imageID;
                        if (verbose) {
                            console.log(`    Image ID: ${imageID}`);
                            console.log(`    Saving to: ${cacheFile}`);
                        }
                        child_process.execSync(`docker image save ${imageID} | gzip > ${cacheFile}`);
                        console.log("  ✓ Cache created successfully");
                    }
                } else if (AWS_BUCKET) {
                    try {
                        child_process.execSync(`aws s3 ls s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`)
                        console.log("  ✓ Cache already exists");
                    } catch (e) {
                        console.log("  ⊕ Creating cache entry");
                        // Read image id from image.json
                        const imageID = JSON.parse(fs.readFileSync(path.join(implFolder, 'image.json')).toString()).imageID;
                        if (verbose) {
                            console.log(`    Image ID: ${imageID}`);
                            console.log(`    Uploading to: s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`);
                        }
                        child_process.execSync(`docker image save ${imageID} | gzip | aws s3 cp - s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`);
                        console.log("  ✓ Cache uploaded successfully");
                    }
                } else {
                    throw new Error("Neither CACHE_DIR nor AWS_BUCKET is set")
                }
            } catch (e) {
                console.log("  ✗ Failed to push image cache:", e)
            }
        } else if (mode == Mode.LoadCache) {
            if (fs.existsSync(path.join(implFolder, 'image.json'))) {
                console.log("  ✓ Already built");
                continue;
            }

            if (verbose) {
                console.log("    Looking for cached image...");
            }

            let cacheHit = false;
            try {
                // Use local cache if CACHE_DIR is set, otherwise fall back to AWS S3
                if (CACHE_DIR) {
                    const cacheFile = path.join(CACHE_DIR, 'imageCache', `${cacheKey}-${arch}.tar.gz`)
                    if (fs.existsSync(cacheFile)) {
                        console.log(`  ✓ Cache hit - loading from ${cacheFile}`);
                        if (verbose) {
                            console.log(`    Running: docker image load -i ${cacheFile}`);
                        }
                        const dockerLoadedMsg = child_process.execSync(`docker image load -i ${cacheFile}`).toString();
                        const loadedImageId = dockerLoadedMsg.match(/Loaded image( ID)?: (.*)/)[2];
                        if (loadedImageId) {
                            if (verbose) {
                                console.log(`    Loaded image ID: ${loadedImageId}`);
                            }
                            fs.writeFileSync(path.join(implFolder, 'image.json'), JSON.stringify({ imageID: loadedImageId }) + "\n");
                            cacheHit = true;
                        }
                    } else {
                        if (verbose) {
                            console.log("    Cache not found in local cache directory");
                        }
                    }
                } else if (AWS_BUCKET) {
                    const cachePath = fs.mkdtempSync(path.join(os.tmpdir(), 'cache'))
                    const archivePath = path.join(cachePath, 'archive.tar.gz')
                    if (verbose) {
                        console.log(`    Downloading from: s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz`);
                    }
                    const dockerLoadedMsg = child_process.execSync(`aws s3 cp s3://${AWS_BUCKET}/imageCache/${cacheKey}-${arch}.tar.gz ${archivePath} && docker image load -i ${archivePath}`).toString();
                    const loadedImageId = dockerLoadedMsg.match(/Loaded image( ID)?: (.*)/)[2];
                    if (loadedImageId) {
                        console.log(`  ✓ Cache hit - loaded ${loadedImageId}`);
                        fs.writeFileSync(path.join(implFolder, 'image.json'), JSON.stringify({ imageID: loadedImageId }) + "\n");
                        cacheHit = true;
                    }
                } else {
                    throw new Error("Neither CACHE_DIR nor AWS_BUCKET is set")
                }
            } catch (e) {
                if (verbose) {
                    console.log("    Cache not found:", e);
                }
            }

            if (cacheHit) {
                if (verbose) {
                    console.log("    Building any remaining artifacts...");
                    console.log("    Running: make -o image.json");
                }
                // We're building using -o image.json. This tells make to
                // not bother building image.json or anything it depends on.
                child_process.execSync(`make -o image.json`, { cwd: implFolder, stdio: 'inherit' })
            } else {
                console.log("  ✗ Cache miss - building from scratch");
                if (verbose) {
                    console.log("    Running: make");
                }
                child_process.execSync(`make`, { cwd: implFolder, stdio: "inherit" })
            }
        }
    }

    console.log("\n=== Cache operations complete ===");
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
