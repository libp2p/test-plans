import { tmpdir } from 'os'
import { promises as fs } from 'fs';
import * as dsl from './dsl'
import { transform } from './testground-transform'
import path from 'path';
import { execSync, spawn } from 'child_process';
import { env } from 'process';

export async function run(testplans: dsl.TestPlans) {
    const dir = path.join(tmpdir(), "testground")

    // Check if directory exists
    try {
        await fs.access(dir)
        await fs.rm(dir, { recursive: true, force: true })
    } catch (e) {
    }
    await fs.mkdir(dir)
    await fs.mkdir(path.join(dir, "testplans"))

    const filesToCreate = transform(testplans)

    await Promise.all(
        filesToCreate.files.map(({ filename, filecontents }) =>
            fs.writeFile(path.join(dir, "testplans", filename), filecontents)
        )
    )

    console.log("Created files in ", dir)

    // Start testground daemon in the background
    const testground = spawn('testground', ['daemon'], {
        env: {
            "TESTGROUND_HOME": dir,
            "PATH": env["PATH"]
        },
        stdio: 'inherit'
    })
    console.log("Testground daemon running", dir)


    try {

        console.log("Importing plan")
        const planImport = execSync(`testground plan import --from ${dir}/testplans --name generated-plan`, {
            env: {
                "TESTGROUND_HOME": dir,
                "PATH": env["PATH"]
            },
            stdio: 'inherit'
        })
        console.log("done importing plan", planImport)

        execSync(
            `cat ${dir}/testplans/composition.toml`, {
            env: {
                "TESTGROUND_HOME": dir,
                "PATH": env["PATH"]
            },
            stdio: 'inherit'
        })

        execSync(
            `testground run composition \
    -f ${dir}/testplans/composition.toml \
    --collect                     \
    --result-file=./results.csv \
    --wait | tee run.out`, {
            env: {
                "TESTGROUND_HOME": dir,
                "PATH": env["PATH"]
            },
            stdio: 'inherit'
        })
    } finally {
        testground.kill('SIGHUP')
    }
}