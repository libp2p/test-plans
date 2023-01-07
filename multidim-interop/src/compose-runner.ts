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
    namespace = namespace.replace(/[^a-zA-Z0-9]/g, "-")
    const dir = path.join(tmpdir(), "compose-runner", namespace)
    const resultsDir = path.join(dir, "results")

    // Check if directory exists
    try {
        await fs.access(dir)
        await fs.rm(dir, { recursive: true, force: true })
    } catch (e) {
    }
    await fs.mkdir(dir, { recursive: true })
    await fs.mkdir(resultsDir, { recursive: true })
    compose.services!.dialer.volumes! = [ resultsDir + ":/results" ]

    // Create compose.yaml file
    await fs.writeFile(path.join(dir, "compose.yaml"), stringify(compose))

    const upFlags: Array<string> = []
    if (opts.up.exitCodeFrom) {
        upFlags.push(`--exit-code-from=${opts.up.exitCodeFrom}`)
    }
    if (opts.up.renewAnonVolumes) {
        upFlags.push("--renew-anon-volumes")
    }

    // TODO: what's the idiomatic way to do this in JS? ;)
    let result = -1
    try {
        const { stdout, stderr } = await exec(`docker compose -f ${path.join(dir, "compose.yaml")} up ${upFlags.join(" ")}`);
        console.log("Finished:", stdout)
        let buf = await fs.readFile(path.join(resultsDir, "results.json"))
        result = JSON.parse(buf.toString())
    } catch (e) {
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
    return result
}
