
import { tmpdir } from 'os'
import { promises as fs } from 'fs';
import path from 'path';
import { exec as execStd } from 'child_process';
import util from 'util';
import { env } from 'process';
import { ComposeSpecification, PropertiesServices } from "../compose-spec/compose-spec"
import { stringify } from 'yaml';

const exec = util.promisify(execStd);
const timeoutSecs = 3 * 60

export type RunOpts = {
    abortSignal: AbortSignal,
    workingDir: string,
}

export type RunFailure = any

export async function run(namespace: string, compose: ComposeSpecification, opts: RunOpts): Promise<RunFailure | null> {
    const workingDir = opts.workingDir
    try {
        await fs.mkdir(workingDir, { recursive: true })
    } catch { }

    for (const [name, service] of Object.entries(compose.services)) {
        await expandService(opts.abortSignal, workingDir, service)
    }

    let services = []
    for (const [name, service] of Object.entries(compose.services)) {
        services.push(runService(opts.abortSignal, workingDir, service).then((res) => {
            console.log("Finished:", name, res)
        }))
    }

    const results = await Promise.all(services)
}

async function expandService(abortSignal: AbortSignal, workingDir: string, service: ComposeSpecification['services'][keyof ComposeSpecification['services']]) {
    const image = service.image
    try {
        // return early if image.tar exists
        await fs.access(path.join(workingDir, `${image}.tar`))
        // await fs.rm(workingDir, { recursive: true, force: true })
        return
    } catch { }


    let start = Date.now()
    await fs.mkdir(path.join(workingDir, `${image}-image`), { recursive: true })
    await exec(`docker save ${image} > ${image}.tar`, { cwd: workingDir, signal: abortSignal })
    console.error("docker save took", Date.now() - start, "ms")
    start = Date.now()
    await exec(`tar -xvf './${image}.tar' -C ./${image}-image`, { cwd: workingDir, signal: abortSignal })
    console.error("extraction took", Date.now() - start, "ms")
    start = Date.now()


    // Read the manifest.json file
    const res = JSON.parse(await fs.readFile(path.join(workingDir, `${image}-image/manifest.json`), { encoding: 'utf-8' }))
    const layers = res[0].Layers

    await fs.mkdir(path.join(workingDir, `${image}-container`))

    // Extract the layers
    for (const layer of layers) {
        await exec(`tar -xvf './${image}-image/${layer}' -C ${image}-container`, { cwd: workingDir, signal: abortSignal })
    }
}

async function runService(abortSignal: AbortSignal, workingDir: string, service: ComposeSpecification['services'][keyof ComposeSpecification['services']]): Promise<{ stdout: string, stderr: string }> {
    let start = Date.now()
    const image = service.image

    // Read the manifest.json file
    const res = JSON.parse(await fs.readFile(path.join(workingDir, `${image}-image/manifest.json`), { encoding: 'utf-8' }))
    const layers = res[0].Layers

    // Read the final layer json
    const finalLayer = path.dirname(layers[layers.length - 1])
    const config: any = JSON.parse(await fs.readFile(path.join(workingDir, `${image}-image/${finalLayer}/json`), { encoding: 'utf-8' }))
    console.error("layer extractions took", Date.now() - start, "ms")
    start = Date.now()

    console.log("Config is:")
    console.log(JSON.stringify(config, null, 2))
    console.log(config["Cmd"])
    const cmds = config["config"]["Cmd"]
    const entrypoint = config["config"]["Entrypoint"]
    let cmd = ""

    if (entrypoint != null && entrypoint.length > 0) {
        cmd = entrypoint.join(" ")
    }
    if (cmds != null && cmds.length > 0) {
        cmd += " " + cmds.join(" ")
    }
    if (cmd == "") {
        throw new Error("No command or entrypoint found")
    }


    // parse env array
    const env = {}

    for (const [k, v] of Object.entries(service.image)) {
        env[k] = v.toString()
    }


    for (const e of config["config"]["Env"]) {
        const [k, v] = e.split("=")
        env[k] = v
    }

    // Run chroot with user namespace
    const { stdout, stderr } = await exec(`unshare --user --map-root-user chroot ${image}-container ${cmd}`, {
        cwd: workingDir,
        signal: abortSignal,
        env,
    })
    console.error(cmd, "command took", Date.now() - start, "ms")
    return { stdout, stderr }
}

if (typeof require !== 'undefined' && require.main === module) {
    // Run the test case if this file is run directly.
    run(
        "test",
        { services: { "redis": { image: "1e5fefbc0ede" } } },
        { abortSignal: new AbortController().signal, workingDir: path.join(tmpdir(), "compose-runner", "hello-world") })
}
