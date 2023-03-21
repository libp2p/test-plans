export type BenchmarkResults = {
    benchmarks: Benchmark[],
    // For referencing this schema in JSON
    "$schema"?: string
};

export type Benchmark = {
    name: string,
    unit: "bits/s" | "s",
    results: Result[],

}

export type Result = {
    result: string,
    implementation: string,
    transportStack: string,
    version: string
};