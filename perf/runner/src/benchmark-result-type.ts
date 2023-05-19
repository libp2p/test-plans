export type BenchmarkResults = {
    benchmarks: Benchmark[],
    pings: PingResults,
    iperf: IperfResults,
    // For referencing this schema in JSON
    "$schema"?: string
};

export type PingResults = {
    unit: "s",
    results: number[]
};

export type IperfResults = {
    unit: "bit/s",
    results: number[]
};

export type Benchmark = {
    name: string,
    unit: "bit/s" | "s",
    results: Result[],
    parameters:
}

export type Parameters = {
    uploadBytes: number,
    downloadBytes: number,
}

export type Result = {
    result: ResultValue[],
    implementation: string,
    transportStack: string,
    version: string
};

export type ResultValue = {
    connectionEstablishedSeconds: number,
    uploadSeconds: number,
    downloadSeconds: number,
};

export type Comparison = {
    name: string,
    result: number,
}
