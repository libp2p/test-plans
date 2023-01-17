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
        const { stdout, stderr } = await exec(`docker compose -f ${path.join(dir, "compose.yaml")} up ${upFlags.join(" ")}`);
        console.log("Finished:", stdout)
    } catch (e: any) {
        console.log("Failure", e)
        if (e !== null && typeof e === "object" && typeof e["stdout"] === "string") {
            if (e["stdout"].match(/dialer.*ping successful/i) !== null) {
                // The ping succeeded, but the listener exited first. Common if
                // the dialer tear-down is slow as is the case with browser
                // tests.
                return null
            }
        }
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