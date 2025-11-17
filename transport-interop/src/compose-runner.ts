import { tmpdir } from 'os'
import { promises as fs } from 'fs';
import path from 'path';
import { exec as execStd } from 'child_process';
import util from 'util';
import { ComposeSpecification, PropertiesServices } from "../compose-spec/compose-spec";
import { stringify } from 'yaml';
import { dialerStdout, dialerTimings } from './compose-stdout-helper';

const exec = util.promisify(execStd);
const timeoutSecs = getTimeout();

function getTimeout (): number {
    const timeout = parseInt(process.env.TIMEOUT, 10)

    if (isNaN(timeout)) {
        return 10 * 60
    }

    return timeout
}

export type RunOpts = {
    up: {
        exitCodeFrom: string
        renewAnonVolumes?: boolean
    }
}

export type RunFailure = any

function shouldSaveLogs(): boolean {
    // Save logs if SAVE_LOGS env var is set to "true", "1", or "failures" (default: save failures only)
    const saveLogs = process.env.SAVE_LOGS || "failures"
    return saveLogs === "true" || saveLogs === "1" || saveLogs === "failures"
}

function shouldSaveAllLogs(): boolean {
    // Save logs for all tests (including successful ones) if SAVE_LOGS=all
    const saveLogs = process.env.SAVE_LOGS
    return saveLogs === "all" || saveLogs === "true" || saveLogs === "1"
}

function getLogsDir(): string {
    // Use LOGS_DIR env var if set, otherwise use ./logs relative to current working directory
    return process.env.LOGS_DIR || path.join(process.cwd(), "logs")
}

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
    // Some docker compose environments don't like the name field to have special characters
    const sanitizedComposeName = compose?.name.replace(/[^a-zA-Z0-9_-]/g, "_")
    await fs.writeFile(path.join(dir, "compose.yaml"), stringify({ ...compose, name: sanitizedComposeName }))

    const upFlags: Array<string> = []
    if (opts.up.exitCodeFrom) {
        upFlags.push(`--exit-code-from=${opts.up.exitCodeFrom}`)
    }
    if (opts.up.renewAnonVolumes) {
        upFlags.push("--renew-anon-volumes")
    }

    let stdout = ""
    let stderr = ""
    let testFailed = false

    try {
        const result = await exec(`docker compose -f ${path.join(dir, "compose.yaml")} up ${upFlags.join(" ")}`, {
            signal: AbortSignal.timeout(1000 * timeoutSecs)
        })
        stdout = result.stdout
        stderr = result.stderr

        try {
            const testResultsParsed = dialerTimings(dialerStdout(stdout))
            console.log("Finished:", namespace, testResultsParsed)
        } catch (e) {
            testFailed = true
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
        testFailed = true
        // Extract stdout/stderr from error if available
        if (e.stdout) stdout = e.stdout
        if (e.stderr) stderr = e.stderr
        console.log("Failure", e)
        
        // Save logs for failures
        if (shouldSaveLogs()) {
            await saveTestLogs(namespace, sanitizedNamespace, stdout, stderr)
        }
        
        return e
    } finally {
        try {
            const { stdout: downStdout, stderr: downStderr } = await exec(`docker compose -f ${path.join(dir, "compose.yaml")} down`);
            // Append docker down output to stderr for completeness
            if (downStderr) stderr += "\n\n=== Docker Compose Down ===\n" + downStderr
        } catch (e) {
            console.log("Failed to compose down", e)
        }
        
        // Save logs for successful tests if SAVE_LOGS=all
        if (!testFailed && shouldSaveAllLogs()) {
            await saveTestLogs(namespace, sanitizedNamespace, stdout, stderr)
        }
        
        await fs.rm(dir, { recursive: true, force: true })
    }
}

async function saveTestLogs(namespace: string, sanitizedNamespace: string, stdout: string, stderr: string): Promise<void> {
    try {
        const logsDir = getLogsDir()
        await fs.mkdir(logsDir, { recursive: true })
        
        const logFile = path.join(logsDir, `${sanitizedNamespace}.log`)
        const logContent = `=== Test: ${namespace} ===\n\n=== STDOUT ===\n${stdout}\n\n=== STDERR ===\n${stderr}\n`
        
        await fs.writeFile(logFile, logContent, 'utf-8')
    } catch (e) {
        // Don't fail the test if log saving fails
        console.log("Warning: Failed to save logs", e)
    }
}
