export type TestPlans<RuntimeEnvParams = GenericEnvParams> = {
    testPlans: Array<TestPlan<RuntimeEnvParams>>,
    env?: TestgroundEnv
}

export type TestgroundEnv = { daemon: { scheduler: { task_timeout_min: number } } }

export type TestPlan<RuntimeEnvParams = GenericEnvParams> = {
    name: string,
    instances: Array<Instance<RuntimeEnvParams>>
}

export type Instance<RuntimeEnvParams = GenericEnvParams> = {
    name: string
    copies?: number // defaults to 1
    containerImageID: string
    runtimeEnv: RuntimeEnvParams
}

export type GenericEnvParams = { [key: string]: { toString(): string } }


