import { buildTestSpecs } from "./src/generator"
import { versions } from './versions'
import { promises as fs } from 'fs';
import { run, RunFailure } from "./src/compose-runner"
import { stringify } from "csv-stringify/sync"

const WorkerCount = parseInt(process.env.WORKER_COUNT || "1")

buildTestSpecs(versions).then(async (testSpecs) => {
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

}).then(() => console.log("Run complete"))