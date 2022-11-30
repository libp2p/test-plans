import * as dsl from './dsl'
import * as TOML from '@iarna/toml'

export type TestgroundConfig = {
    files: Array<FileMeta>
}

type FileMeta = {
    filename: string,
    filecontents: string,
}

const testcaseName = "generated-tc"

export function transform(testplans: dsl.TestPlans): TestgroundConfig {
    return {
        files: [
            {
                filename: "composition.toml",
                filecontents: TOML.stringify(generateComposition(testplans))
            },
            {
                filename: "manifest.toml",
                filecontents: TOML.stringify(generateManifest())
            }
        ]
    }
}

function generateComposition(testplans: dsl.TestPlans): {} {
    return {
        metadata: {
            name: "testplans-generated-composition"
        },
        global: {
            builder: "docker:generic",
            plan: "generated-plan",
            case: testcaseName,
            runner: "local:docker"
        },
        groups: generateGroups(testplans),
        runs: generateRuns(testplans),
    }
}

function generateGroups({ testPlans }: dsl.TestPlans): Array<{}> {
    const allInstances: { [key: string]: dsl.Instance } = {}
    // Collect all instance by their container image ID for the top level groups.
    testPlans.forEach(tp => tp.instances.forEach(inst => {
        allInstances[inst.containerImageID] = inst
    }))

    return Object.values(allInstances).map(inst => ({
        id: inst.name.replaceAll(" ", "_") + inst.containerImageID.replaceAll(":", "_"),
        instances: { count: inst.copies ?? 1 },
        run: {
            artifact: inst.containerImageID,
        }
    }))
}

function stringifyRuntimeEnv(env: dsl.GenericEnvParams): { [key: string]: string } {
    const out: { [key: string]: string } = {}
    Object.entries(env).forEach(([key, value]) => {
        out[key] = value.toString()
    })
    return out
}

function generateRuns({ testPlans }: dsl.TestPlans): Array<{}> {
    return testPlans.map(tp => ({
        id: tp.name.replaceAll(" ", "_"),
        groups: tp.instances.map(inst => ({
            id: inst.name.replaceAll(" ", "_") + inst.containerImageID.replaceAll(":", "_"),
            test_params: stringifyRuntimeEnv(inst.runtimeEnv)
        }))
    }))
}

function generateManifest(): {} {
    return {
        name: "generated-plan",
        defaults: {
            builder: "docker:exec", // unused
            runner: "local:docker"
        },
        builders: {
            "docker:exec": { enabled: true },
        },
        runners: {
            "local:docker": { enabled: true },
        },
        testcases: [{
            name: testcaseName,
            instances: {
                min: 1,
                max: 5000,
                default: 1,
            }
        }]
    }
}