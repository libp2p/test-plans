
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
}

async function expandService(abortSignal: AbortSignal, workingDir: string, service: ComposeSpecification['services'][keyof ComposeSpecification['services']]) {
    const image = service.image
    try {
        // return early if image.tar exists
        await fs.access(path.join(workingDir, `${image}.tar`))
        await fs.rm(workingDir, { recursive: true, force: true })
        // return
    } catch { }


    await fs.mkdir(path.join(workingDir, `${image}-image`))
    await exec(`docker save ${image} > ${image}.tar`, { cwd: workingDir, signal: abortSignal })
    await exec(`tar -xvf ${image}.tar -C ${image}-image`, { cwd: workingDir, signal: abortSignal })

    // Read the manifest.json file
    const res = JSON.parse(await fs.readFile(path.join(workingDir, `${image}-image/manifest.json`), { encoding: 'utf-8' }))
    const layers = res[0].Layers

    await fs.mkdir(path.join(workingDir, `${image}-container`))

    // Extract the layers
    for (const layer of layers) {
        await exec(`tar -xvf ${image}-image/${layer} -C ${image}-container`, { cwd: workingDir, signal: abortSignal })
    }

    // Read the final layer json

    const finalLayer = path.dirname(layers[layers.length - 1])

    const config: any = JSON.parse(await fs.readFile(path.join(workingDir, `${image}-image/${finalLayer}/json`), { encoding: 'utf-8' }))
    console.log("Config is:")
    console.log(JSON.stringify(config, null, 2))
    console.log(config["Cmd"])
    const cmds = config["config"]["Cmd"]
    let cmd = ""

    if (cmds != null && cmds.length > 0) {
        cmd = cmds[0]
    } else {
        throw new Error("No command found")
    }

    // Run chroot with user namespace
    await exec(`unshare --user --map-root-user chroot ${image}-container "${cmd}"`, { cwd: workingDir, signal: abortSignal })
}

if (typeof require !== 'undefined' && require.main === module) {
    // Run the test case if this file is run directly.
    run(
        "test",
        { services: { "hello-world": { image: "hello-world" } } },
        { abortSignal: new AbortController().signal, workingDir: path.join(tmpdir(), "compose-runner", "hello-world") }).then(() => console.log("Done"))
}
