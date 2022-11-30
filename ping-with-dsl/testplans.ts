import { TestPlans } from "dsl/src/dsl"
import { run } from "dsl/src/testground-runner"
import goV0230 from "./go/v0.23.0/image.json"
import rustV0490 from "./rust/image.0.49.0.json"

type PingParams = {
    max_latency_ms: number,
    iterations: number,
}

const testplans: TestPlans<PingParams> = {
    testPlans: [
        {
            name: "Go v0.23",
            instances: [
                {
                    name: "Go v0.23 x Go v0.23",
                    containerImageID: goV0230.imageID,
                    copies: 2,
                    runtimeEnv: {
                        "max_latency_ms": 500,
                        "iterations": 5,
                    }
                },
            ]
        },
        {
            name: "Rust v0.49.0",
            instances: [
                {
                    name: "Rust v0.49.0 x Rust v0.49.0",
                    containerImageID: rustV0490.imageID,
                    copies: 2,
                    runtimeEnv: {
                        "max_latency_ms": 500,
                        "iterations": 5,
                    }
                }
            ]

        },
        {
            name: "Go v0.23 x Rust v0.49.0",
            instances: [
                {
                    name: "Go v0.23",
                    containerImageID: goV0230.imageID,
                    runtimeEnv: {
                        "max_latency_ms": 500,
                        "iterations": 5,
                    }
                },
                {
                    name: "Rust v0.49.0",
                    containerImageID: rustV0490.imageID,
                    runtimeEnv: {
                        "max_latency_ms": 500,
                        "iterations": 5,
                    }
                }
            ]
        }
    ]
}

run(testplans).then(() => console.log("Run complete"))