import { execSync } from 'child_process';
import { versions } from './versions';
import yargs from 'yargs';
import fs from 'fs';
import { BenchmarkResults, Benchmark, Result } from './benchmark-result-type';

async function main(clientPublicIP: string, serverPublicIP: string) {
    copyAndBuildPerfImplementations(serverPublicIP);
    copyAndBuildPerfImplementations(clientPublicIP);

    const benchmarkResults: BenchmarkResults = {
        benchmarks: [
            runBenchmarkAcrossVersions({
                name: "Single Connection throughput – Upload 100 MiB",
                clientPublicIP,
                serverPublicIP,
                uploadBytes: 100 << 20,
                downloadBytes: 0,
                unit: "bit/s",
                iterations: 5,
            }),
            runBenchmarkAcrossVersions({
                name: "Single Connection throughput – Download 100 MiB",
                clientPublicIP,
                serverPublicIP,
                uploadBytes: 0,
                downloadBytes: 100 << 20,
                unit: "bit/s",
                iterations: 5,
            }),
            runBenchmarkAcrossVersions({
                name: "Connection establishment + 1 byte round trip latencies",
                clientPublicIP,
                serverPublicIP,
                uploadBytes: 1,
                downloadBytes: 1,
                unit: "s",
                iterations: 100,
            }),
        ],
    };

    // Save results to benchmark-results.json
    fs.writeFileSync('./benchmark-results.json', JSON.stringify(benchmarkResults, null, 2));

    console.error("== done");
}

interface ArgsRunBenchmarkAcrossVersions {
    name: string,
    clientPublicIP: string;
    serverPublicIP: string;
    uploadBytes: number,
    downloadBytes: number,
    unit: "bit/s" | "s",
    iterations: number,
}

function runBenchmarkAcrossVersions(args: ArgsRunBenchmarkAcrossVersions): Benchmark {
    console.error(`= Benchmark ${args.name}`)

    const results: Result[] = [];

    for (const version of versions) {
        console.error(`== Version ${version.implementation}/${version.id}`)

        console.error(`=== Starting server ${version.implementation}/${version.id}`);

        let killCMD = `ssh ec2-user@${args.serverPublicIP} 'kill $(cat pidfile); rm pidfile; rm server.log || true'`;
        const killSTDOUT = execCommand(killCMD);
        console.error(killSTDOUT);

        let serverCMD = `ssh ec2-user@${args.serverPublicIP} 'nohup ./impl/${version.implementation}/${version.id}/perf --run-server --secret-key-seed 0 > server.log 2>&1 & echo \$! > pidfile '`;
        const serverSTDOUT = execCommand(serverCMD);
        console.error(serverSTDOUT);

        for (const transportStack of version.transportStacks) {
            const latencies = runClient({
                clientPublicIP: args.clientPublicIP,
                serverPublicIP: args.serverPublicIP,
                id: version.id,
                implementation: version.implementation,
                transportStack: transportStack,
                uploadBytes: args.uploadBytes,
                downloadBytes: args.downloadBytes,
                iterations: args.iterations,
            }).latencies.map(l => {
                switch(args.unit) {
                    case "bit/s":
                        return (args.uploadBytes + args.downloadBytes) * 8 / l;
                    case "s":
                        return l;
                }
            });

            results.push({
                result: latencies,
                implementation: version.implementation,
                version: version.id,
                transportStack: transportStack,
            });
        }
    };

    return {
        name: args.name,
        unit: args.unit,
        results,
    };
}

interface ArgsRunBenchmark {
    clientPublicIP: string;
    serverPublicIP: string;
    serverAddress?: string;
    id: string,
    implementation: string,
    transportStack: string,
    uploadBytes: number,
    downloadBytes: number,
    iterations: number,
}

interface Latencies {
    latencies: number[];
}


function runClient(args: ArgsRunBenchmark): Latencies {
    console.error(`=== Starting client ${args.implementation}/${args.id}/${args.transportStack}`);

    const perfCMD = `./impl/${args.implementation}/${args.id}/perf --server-ip-address ${args.serverPublicIP} --transport ${args.transportStack} --upload-bytes ${args.uploadBytes} --download-bytes ${args.downloadBytes}`
    const cmd = `ssh ec2-user@${args.clientPublicIP} 'for i in {1..${args.iterations}}; do ${perfCMD}; done'`

    const stdout = execCommand(cmd);
    // TODO: Does it really still make sense for the binary to return an array?
    const lines = stdout.toString().trim().split('\n');

    const combined: Latencies = {
        latencies: [],
    };

    for (const line of lines) {
        const latencies = JSON.parse(line) as Latencies;
        combined.latencies.push(...latencies.latencies);
    }

    return combined;
}

function execCommand(cmd: string): string {
    try {
        const stdout = execSync(cmd, {
            encoding: 'utf8',
            stdio: [process.stdin, 'pipe', process.stderr],
        });
        return stdout;
    } catch (error) {
        console.error((error as Error).message);
        process.exit(1);
    }
}

function copyAndBuildPerfImplementations(ip: string) {
    const stdout = execCommand(`rsync -avz --progress ../impl ec2-user@${ip}:/home/ec2-user`);
    console.log(stdout.toString());

    const stdout2 = execCommand(`ssh ec2-user@${ip} 'cd impl && make'`);
    console.log(stdout2.toString());
}

const argv = yargs
    .options({
        'client-public-ip': {
            type: 'string',
            demandOption: true,
            description: 'Client public IP address',
        },
        'server-public-ip': {
            type: 'string',
            demandOption: true,
            description: 'Server public IP address',
        },
    })
    .command('help', 'Print usage information', yargs.help)
    .parseSync();

main(argv['client-public-ip'] as string, argv['server-public-ip'] as string);
