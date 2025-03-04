export interface BenchmarkResults {
    benchmarks: Benchmark[]
    pings: PingResults
    iperf: IperfResults
    // For referencing this schema in JSON
    "$schema"?: string
}

export interface PingResults {
    unit: "s"
    results: number[]
}

export interface IperfResults {
    unit: "bit/s"
    results: number[]
}

export interface Benchmark {
    name: string
    unit: "bit/s" | "s"
    results: Result[]
    parameters: Parameters
}

export interface Parameters {
    uploadBytes: number
    downloadBytes: number
}

export interface Result {
    implementation: string
    transportStack: string
    version: string
    result: ResultValue[]
};

export interface ResultValue {
    type: "itermediate" | "final"
    time_seconds: number
    upload_bytes: number
    download_bytes: number
}

export interface Comparison {
    name: string
    result: number
}
