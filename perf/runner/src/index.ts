import { execSync } from 'child_process';
import { versions } from './versions';
import yargs from 'yargs';
import { BenchmarkResults, Benchmark } from './benchmark-result-type';

async function main(clientPublicIP: string, serverPublicIP: string) {
    const benchmark: Benchmark = {
        name: "",
        unit: "s",
        results: [],
        comparisons: [],
    };


    for (const version of versions) {
        for (const transportStack of version.transportStacks) {
            const latencies = runBenchmark({
                clientPublicIP: clientPublicIP,
                serverPublicIP: serverPublicIP,
                dockerImageId: version.containerImageID,
                transportStack: transportStack,
                uploadBytes: 1,
                downloadBytes: 1,
                nTimes: 10,
            });

            benchmark.results.push({
                result: latencies.latencies,
                implementation: "",
                version: version.id,
                transportStack: "",
            });
        }
    };

    const benchmarkResults: BenchmarkResults = {
        benchmarks: [benchmark],
    };
    console.log(JSON.stringify(benchmarkResults, null, 2));
}

interface Latencies {
    latencies: number[];
}

interface Args {
    clientPublicIP: string;
    serverPublicIP: string;
    dockerImageId: string;
    transportStack: string,
    uploadBytes: number,
    downloadBytes: number,
    nTimes: number,
}

function runBenchmark(args: Args): Latencies {
    let serverAddress: string;

    switch (args.transportStack) {
        case 'tcp':
            serverAddress = `/ip4/${args.serverPublicIP}/tcp/4001`;
            break;
        case 'quic-v1':
            serverAddress = `/ip4/${args.serverPublicIP}/udp/4001/quic-v1`;
            break;
        default:
            console.error("Unsupported transport stack ${args.transportStack}");
            process.exit(1);

    }

    const binFlags = `--server-address ${serverAddress} --upload-bytes ${args.uploadBytes} --download-bytes ${args.downloadBytes} --n-times ${args.nTimes}`
    const dockerCMD = `docker run --rm --entrypoint perf-client ${args.dockerImageId} ${binFlags}`
    const cmd = `ssh ec2-user@${args.clientPublicIP} ${dockerCMD}`;

    try {
        const stdout = execSync(cmd, {
            encoding: 'utf8',
            stdio: [process.stdin, 'pipe', process.stderr],
        });
        const latencies: Latencies = JSON.parse(stdout.toString());
        return latencies;
    } catch (error) {
        console.error((error as Error).message);
        process.exit(1);
    }
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
