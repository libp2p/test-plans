import { buildTestSpecs } from "./src/generator"
import { Version, versions } from "./versions"
import { promises as fs } from "fs";
import {ExecException, run} from "./src/compose-runner"
import { stringify } from "csv-stringify/sync"
import { stringify as YAMLStringify } from "yaml"
import yargs from "yargs/yargs"
import path from "path";

(async () => {
    const WorkerCount = parseInt(process.env.WORKER_COUNT || "1")
    const argv = await yargs(process.argv.slice(2))
        .options({
            'name-filter': {
                description: 'Only run tests including this name',
                default: "",
            },
            'name-ignore': {
                description: 'Do not run any tests including this name',
                default: "",
            },
            'no-run': {
                description: "Don't run any tests, just generate the docker-compose files",
                default: false,
                type: 'boolean'
            },
            'extra-versions-dir': {
                description: 'Look for extra versions in this directory. Version files must be in json format',
                default: "",
                type: 'string'
            },
            'extra-version': {
                description: 'Paths to JSON files for additional versions to include in the test matrix',
                default: [],
                type: 'array'
            },
        })
        .help()
        .version(false)
        .alias('help', 'h').argv;
    const extraVersionsDir = argv.extraVersionsDir
    const extraVersions: Array<Version> = []
    if (extraVersionsDir !== "") {
        try {
            const files = await fs.readdir(extraVersionsDir);
            for (const file of files) {
                const contents = await fs.readFile(path.join(extraVersionsDir, file))
                extraVersions.push(...JSON.parse(contents.toString()))
            }
        } catch (err) {
            console.error("Error reading extra versions")
            console.error(err);
        }
    }

    for (let versionPath of argv.extraVersion.filter(p => p !== "")) {
        const contents = await fs.readFile(versionPath);
        extraVersions.push(JSON.parse(contents.toString()))
    }

    let nameFilter: string | null = argv["name-filter"]
    if (nameFilter === "") {
        nameFilter = null
    }
    let nameIgnore: string | null = argv["name-ignore"]
    if (nameIgnore === "") {
        nameIgnore = null
    }

    let routerImageId = JSON.parse(await fs.readFile(path.join(".", "router", "image.json"), "utf-8")).imageID;
    let relayImageId = JSON.parse(await fs.readFile(path.join(".", "rust-relay", "image.json"), "utf-8")).imageID;

    const routerDelay = 100;
    const relayDelay = 25;

    const rttRelayedConnection = routerDelay * 2 + relayDelay * 2;
    const rttDirectConnection = routerDelay * 2;

    const assetDir = path.join(__dirname, "runs");

    let testSpecs = await buildTestSpecs(versions.concat(extraVersions), nameFilter, nameIgnore, routerImageId, relayImageId, routerDelay, relayDelay, assetDir)


    if (argv["emit-only"]) {
        for (const testSpec of testSpecs) {
            console.log("## " + testSpec.name)
            console.log(YAMLStringify(testSpec))
            console.log("\n\n")
        }
        return
    }

    console.log(`Running ${testSpecs.length} tests`)
    const failures: Array<{ name: String, e: ExecException }> = []
    const statuses: Array<string[]> = [["name", "outcome"]]
    const workers = new Array(WorkerCount).fill({}).map(async () => {
        while (true) {
            const testSpec = testSpecs.pop()
            if (testSpec == null) {
                return
            }
            const name = testSpec.name;
            if (!name) {
                console.warn("Skipping testSpec without name")
                continue;
            }

            console.log("Running test spec: " + name)

            try {
                const report = await run(name, testSpec, assetDir);
                const rttDifference = Math.abs(report.rtt_to_holepunched_peer_millis - rttDirectConnection);

                if (rttDifference > 5) {
                    // Emit a warning but don't do anything for now.
                    console.warn(`Expected RTT of direction connection to be ~${rttDirectConnection}ms but was ${report.rtt_to_holepunched_peer_millis}ms`)
                }

                statuses.push([name, "success"])
            } catch (e) {
                failures.push({ name, e })
                statuses.push([name, "failure"])
            }
        }
    })
    await Promise.all(workers)

    console.log(`${failures.length} failures:`)

    for (const [number, {name, e}] of failures.entries()) {
        console.log(`---------- ${name} ---------- (${number + 1} / ${failures.length + 1})`);
        console.log(e.stdout)
        console.log(e.stderr)
    }

    await fs.writeFile("results.csv", stringify(statuses))

    console.log("Run complete")
})()
