import { tmpdir } from 'os'
import { promises as fs } from 'fs';
import path from 'path';
import { exec as execStd } from 'child_process';
import util from 'util';
import { env } from 'process';
import { ComposeSpecification, PropertiesServices } from "../compose-spec/compose-spec"
import { stringify } from 'yaml';

const exec = util.promisify(execStd);

export type RunOpts = {
    up: {
        exitCodeFrom: string
        renewAnonVolumes?: boolean
    }
}

export type RunFailure = any

export async function run(namespace: string, compose: ComposeSpecification, opts: RunOpts): Promise<RunFailure | null> {
    // sanitize namespace
    const sanitizedNamespace = namespace.replace(/[^a-zA-Z0-9]/g, "-")
    const dir = path.join(tmpdir(), "compose-runner", sanitizedNamespace)

    // Check if directory exists
    try {
        await fs.access(dir)
        await fs.rm(dir, { recursive: true, force: true })
    } catch (e) {
    }
    await fs.mkdir(dir, { recursive: true })

    // Create compose.yaml file
    await fs.writeFile(path.join(dir, "compose.yaml"), stringify(compose))

    const upFlags: Array<string> = []
    if (opts.up.exitCodeFrom) {
        upFlags.push(`--exit-code-from=${opts.up.exitCodeFrom}`)
    }
    if (opts.up.renewAnonVolumes) {
        upFlags.push("--renew-anon-volumes")
    }

    try {
        const timeoutSecs = 3 * 60
        let timeoutId
        const { stdout, stderr } =
            (await Promise.race([
                exec(`docker compose -f ${path.join(dir, "compose.yaml")} up ${upFlags.join(" ")}`),
                // Timeout - uses any type because this will only reject the promise.
                new Promise<any>((resolve, reject) => { timeoutId = setTimeout(() => reject("Timeout"), 1000 * timeoutSecs) })
            ]))
        clearTimeout(timeoutId)
        const testResults = stdout.match(/.*dialer.*({.*)/)
        if (testResults === null || testResults.length < 2) {
            throw new Error("Test JSON results not found")
        }
        const testResultsParsed = JSON.parse(testResults[1])
        console.log("Finished:", namespace, testResultsParsed)
    } catch (e: any) {
        console.log("Failure", e)
        return e
    } finally {
        try {
            const { stdout, stderr } = await exec(`docker compose -f ${path.join(dir, "compose.yaml")} down`);
        } catch (e) {
            console.log("Failed to compose down", e)
        }
        await fs.rm(dir, { recursive: true, force: true })
    }
}