import {promises as fs} from 'fs';
import path from 'path';
import {exec as execStd} from 'child_process';
import util from 'util';
import {ComposeSpecification} from "../compose-spec/compose-spec";
import {stringify} from 'yaml';
import {sanitizeComposeName} from "./lib";

const exec = util.promisify(execStd);

export async function run(compose: ComposeSpecification, rootAssetDir: string, dryRun: boolean): Promise<Report | null> {
    const sanitizedComposeName = sanitizeComposeName(compose.name)
    const assetDir = path.join(rootAssetDir, sanitizedComposeName);

    await fs.mkdir(assetDir, { recursive: true })


    // Create compose.yaml file
    // Some docker compose environments don't like the name field to have special characters
    const composeYmlPath = path.join(assetDir, "docker-compose.yaml");
    await fs.writeFile(composeYmlPath, stringify({ ...compose, name: sanitizedComposeName }))

    if (dryRun) {
        return null;
    }

    const stdoutLogFile = path.join(assetDir, `stdout.log`);
    const stderrLogFile = path.join(assetDir, `stderr.log`);

    try {
        const { stdout, stderr } = await exec(`docker compose -f ${composeYmlPath} up --exit-code-from client --abort-on-container-exit`, { timeout: 60 * 1000 })

        await fs.writeFile(stdoutLogFile, stdout);
        await fs.writeFile(stderrLogFile, stderr);

        return JSON.parse(lastStdoutLine(stdout, "client", sanitizedComposeName)) as Report
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

export interface ExecException extends Error {
    cmd?: string | undefined;
    killed?: boolean | undefined;
    code?: number | undefined;
    signal?: NodeJS.Signals | undefined;
    stdout: string;
    stderr: string;
}

function isExecException(candidate: unknown): candidate is ExecException {
    return candidate && typeof candidate === 'object' && 'cmd' in candidate;
}

// Report is the single line the client prints on stdout on a successful reachability check.
interface Report {
    reachable: boolean
    tested_addr: string
}

export function lastStdoutLine(stdout: string, component: string, composeName: string): string {
    // Docker Compose prefixes each attached log line with the container name and
    // a "|" separator. The exact prefix varies by Compose version: older versions
    // use "<project>-<service>-<index>" while newer ones use just "<service>-<index>".
    // Match the prefix segment ending in "<component>-1" after removing carriage
    // returns and ANSI escape sequences, and drop the "exited with code" notice,
    // which carries no separator.
    const contentLines = stdout
        .split("\n")
        .map(line => line.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\r/g, "").trimStart())
        .filter(line => line.includes("|"))
        .filter(line => line.slice(0, line.indexOf("|")).trim().endsWith(`${component}-1`))
        .map(line => line.slice(line.indexOf("|") + 1).trim());

    const lastLine = contentLines.pop();
    if (lastLine === undefined) {
        throw new Error(`Found no stdout output for the ${component} service in compose ${composeName}`);
    }

    return lastLine;
}
