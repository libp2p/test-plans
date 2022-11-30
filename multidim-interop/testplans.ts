import { run } from "dsl/src/testground-runner"
import { buildTestplans } from "./composer"
import { versions } from './versions'

buildTestplans(versions).then((testplans) => run(testplans)).then(() => console.log("Run complete"))