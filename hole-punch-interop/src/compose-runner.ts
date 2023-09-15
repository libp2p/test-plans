import {tmpdir} from 'os'
import {promises as fs} from 'fs';
import path from 'path';
import {exec as execStd} from 'child_process';
import util from 'util';
import {ComposeSpecification} from "../compose-spec/compose-spec";
import {stringify} from 'yaml';

const exec = util.promisify(execStd);

export type RunFailure = any

export async function run(namespace: string, compose: ComposeSpecification): Promise<RunFailure | null> {
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
    // Some docker compose environments don't like the name field to have special characters
    const sanitizedComposeName = compose?.name.replace(/[^a-zA-Z0-9_-]/g, "_")
    await fs.writeFile(path.join(dir, "compose.yaml"), stringify({ ...compose, name: sanitizedComposeName }))

    try {
        const { stdout, stderr } = await exec(`docker compose -f ${path.join(dir, "compose.yaml")} up --exit-code-from alice --abort-on-container-exit`, { timeout: 15 * 1000 })
        try {
            // TODO: Parse ping here.

            console.log("Finished:", namespace)
        } catch (e) {
            console.log("Failed to parse test results.")
            console.log("stdout:")
            console.log(stdout)
            console.log("")
            console.log("stderr:")
            console.log(stderr)
            console.log("")
            throw e
        }
    } catch (e: any) {
        console.log("Failure", e)
        return e
    } finally {
        try {
            await exec(`docker compose -f ${path.join(dir, "compose.yaml")} down`);
        } catch (e) {
            console.log("Failed to compose down", e)
        }
        await fs.rm(dir, { recursive: true, force: true })
    }
}
