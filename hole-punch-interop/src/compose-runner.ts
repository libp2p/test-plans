import {tmpdir} from 'os'
import {promises as fs} from 'fs';
import path from 'path';
import {exec as execStd} from 'child_process';
import util from 'util';
import {ComposeSpecification} from "../compose-spec/compose-spec";
import {stringify} from 'yaml';
import {sanitizeComposeName} from "./lib";

const exec = util.promisify(execStd);

export type RunFailure = any

export async function run(namespace: string, compose: ComposeSpecification, logDir: string): Promise<Report> {
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
    await fs.mkdir(logDir, { recursive: true })

    // Create compose.yaml file
    // Some docker compose environments don't like the name field to have special characters
    const sanitizedComposeName = sanitizeComposeName(compose.name)
    await fs.writeFile(path.join(dir, "compose.yaml"), stringify({ ...compose, name: sanitizedComposeName }))

    const stdoutLogFile = path.join(logDir, `${sanitizedComposeName}.stdout`);
    const stderrLogFile = path.join(logDir, `${sanitizedComposeName}.stderr`);

    try {
        const { stdout, stderr } = await exec(`docker compose -f ${path.join(dir, "compose.yaml")} up --exit-code-from alice --abort-on-container-exit`, { timeout: 60 * 1000 })

        await fs.writeFile(stdoutLogFile, stdout);
        await fs.writeFile(stderrLogFile, stderr);

        return JSON.parse(lastStdoutLine(stdout, "alice", sanitizedComposeName)) as Report
    } catch (e: unknown) {
        if (isExecException(e)) {
            await fs.writeFile(stdoutLogFile, e.stdout)
            await fs.writeFile(stderrLogFile, e.stderr)
        }

        throw e
    } finally {
        try {
            await exec(`docker compose -f ${path.join(dir, "compose.yaml")} down`);
        } catch (e) {
            console.log("Failed to compose down", e)
        }
        await fs.rm(dir, { recursive: true, force: true })
    }
}

interface ExecException extends Error {
    cmd?: string | undefined;
    killed?: boolean | undefined;
    code?: number | undefined;
    signal?: NodeJS.Signals | undefined;
    stdout: string;
    stderr: string;
}

function isExecException(candidate: unknown): candidate is ExecException {
    if (candidate && typeof candidate === 'object' && 'cmd' in candidate) {
        return true;
    }
    return false;
}

interface Report {
    rtt_to_holepunched_peer_millis: number
}

export function lastStdoutLine(stdout: string, component: string, composeName: string): string {
    const allComponentStdout = stdout.split("\n").filter(line => line.startsWith(`${composeName}-${component}-1`));

    const exitMessage = allComponentStdout.pop();
    const lastLine = allComponentStdout.pop();

    const [front, componentStdout] = lastLine.split("|");

    return componentStdout.trim()
}
