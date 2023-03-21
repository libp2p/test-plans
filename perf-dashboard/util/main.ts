import * as tsj from "ts-json-schema-generator";
import * as fs from "fs";
// const fs = require("fs");

/** @type {import('ts-json-schema-generator/dist/src/Config').Config} */
const config = {
    path: "../benchmark-result-type.ts",
    tsconfig: "./tsconfig.json",
    type: "BenchmarkResults", // Or <type-name> if you want to generate schema for that one type only
};

const output_path = "../benchmarks.schema.json";

const schema = tsj.createGenerator(config).createSchema(config.type);
const schemaString = JSON.stringify(schema, null, 2);
fs.writeFile(output_path, schemaString, (err) => {
    if (err) throw err;
});