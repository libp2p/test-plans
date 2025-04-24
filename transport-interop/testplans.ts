import { buildTestSpecs } from "./src/generator"
import { Version, versions } from "./versions"
import { promises as fs } from "fs";
import { run, RunFailure } from "./src/compose-runner"
import { stringify } from "csv-stringify/sync"
import { stringify as YAMLStringify } from "yaml"
import yargs from "yargs/yargs"
import path from "path";

(async () => {
    const WorkerCount = parseInt(process.env.WORKER_COUNT || "1")
    const argv = await yargs(process.argv.slice(2))
        .options({
            'name-filter': {
                description: 'Only run tests including any of these names (pipe separated)',
                default: "",
            },
            'name-ignore': {
                description: 'Do not run any tests including any of these names (pipe separated)',
                default: "",
            },
            'emit-only': {
                alias: 'e',
                description: 'Only print the compose.yaml file',
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
            'verbose': {
                description: 'Enable verbose logging',
                default: false,
                type: 'boolean'
            }
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

    const verbose: boolean = argv.verbose

    let nameFilter: string[] | null = null
    const rawNameFilter: string | undefined = argv["name-filter"]
    if (rawNameFilter) {
        if (verbose) {
            console.log("rawNameFilter: " + rawNameFilter)
        }
        nameFilter = rawNameFilter.split('|').map(item => item.trim());
    }
    if (nameFilter) {
        console.log("Name Filters:")
        nameFilter.map(n => console.log("\t" + n))
    }
    let nameIgnore: string[] | null = null
    const rawNameIgnore: string | undefined = argv["name-ignore"]
    if (rawNameIgnore) {
        if (verbose) {
            console.log("rawNameIgnore: " + rawNameIgnore)
        }
        nameIgnore = rawNameIgnore.split('|').map(item => item.trim());
    }
    if (nameIgnore) {
        console.log("Name Ignores:")
        nameIgnore.map(n => console.log("\t" + n))
    }

    let testSpecs = await buildTestSpecs(versions.concat(extraVersions), nameFilter, nameIgnore, verbose)

    if (argv["emit-only"]) {
        for (const testSpec of testSpecs) {
            console.log("## " + testSpec.name)
            console.log(YAMLStringify(testSpec))
            console.log("\n\n")
        }
        return
    }

    console.log(`Running ${testSpecs.length} tests`)
    const failures: Array<RunFailure> = []
    const statuses: Array<string[]> = [["name", "outcome"]]
    const workers = new Array(WorkerCount).fill({}).map(async () => {
        while (true) {
            const testSpec = testSpecs.pop()
            if (testSpec == null) {
                return
            }
            console.log("Running test spec: " + testSpec.name)
            const failure = await run(testSpec.name || "unknown test", testSpec, { up: { exitCodeFrom: "dialer", renewAnonVolumes: true }, })
            if (failure != null) {
                failures.push(failure)
                statuses.push([testSpec.name || "unknown test", "failure"])
            } else {
                statuses.push([testSpec.name || "unknown test", "success"])
            }
        }
    })
    await Promise.all(workers)

    console.log(`${failures.length} failures`, failures)
    await fs.writeFile("results.csv", stringify(statuses))

    console.log("Run complete")
})()
