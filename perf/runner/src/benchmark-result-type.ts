export type BenchmarkResults = {
    benchmarks: Benchmark[],
    // For referencing this schema in JSON
    "$schema"?: string
};

export type Benchmark = {
    name: string,
    unit: "bit/s" | "s",
    results: Result[],
    comparisons: Comparison[],

}

export type Result = {
    result: number[],
    implementation: string,
    transportStack: string,
    version: string
};

export type Comparison = {
    name: string,
    result: number,
}
