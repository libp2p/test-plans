import { TestPlans } from "../src"
import { run } from "../src/testground-runner"

function example() {
    const testplans: TestPlans = {
        testPlans: [{
            name: "Simple Ping",
            instances: [{
                name: "Simple thing 1",
                containerImageID: "sha256:8541da386bfb89b5f9652f452e2f24b773ebc0886bb5a92406439417c159536f",
                runtimeEnv: {}
            }]
        }]

    }
    run(testplans)
}

example()