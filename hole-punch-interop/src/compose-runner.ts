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

export async function run(namespace: string, compose: ComposeSpecification, rootAssetDir: string): Promise<Report> {
    const sanitizedComposeName = sanitizeComposeName(compose.name)
    const assetDir = path.join(rootAssetDir, sanitizedComposeName);

    await fs.mkdir(assetDir, { recursive: true })


    // Create compose.yaml file
    // Some docker compose environments don't like the name field to have special characters
    const composeYmlPath = path.join(assetDir, "docker-compose.yaml");
    await fs.writeFile(composeYmlPath, stringify({ ...compose, name: sanitizedComposeName }))

    const stdoutLogFile = path.join(assetDir, `stdout.log`);
    const stderrLogFile = path.join(assetDir, `stderr.log`);

    try {
        const { stdout, stderr } = await exec(`docker compose -f ${composeYmlPath} up --exit-code-from dialer --abort-on-container-exit`, { timeout: 60 * 1000 })

        await fs.writeFile(stdoutLogFile, stdout);
        await fs.writeFile(stderrLogFile, stderr);

        return JSON.parse(lastStdoutLine(stdout, "dialer", sanitizedComposeName)) as Report
    } catch (e: unknown) {
        if (isExecException(e)) {
            await fs.writeFile(stdoutLogFile, e.stdout)
            await fs.writeFile(stderrLogFile, e.stderr)
        }

        throw e
    } finally {
        try {
            await exec(`docker compose -f ${composeYmlPath} down`);
        } catch (e) {
            console.log("Failed to compose down", e)
        }
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
