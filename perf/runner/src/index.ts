import { execSync } from 'child_process';
import { versions } from './versions';
import yargs from 'yargs';
import { BenchmarkResults, Benchmark } from './benchmark-result-type';

interface Latencies {
    latencies: number[];
}

interface Args {
    clientPublicIP: string;
    serverPublicIP: string;
    dockerImageId: string;
    transportStack: string,
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

    const cmd = `echo This message goes to stderr >&2 && ssh ec2-user@${args.clientPublicIP} docker run --rm --entrypoint perf-client ${args.dockerImageId} --server-address ${serverAddress} --upload-bytes 1 --download-bytes 1 --n-times 10`;

    try {
        const  stdout = execSync(cmd, {
            encoding: 'utf8',
            stdio: [process.stdin, 'pipe', process.stderr],
        });
        console.log(`output: ${stdout}`);
        const latencies: Latencies = JSON.parse(stdout.toString());
        return latencies;
    } catch (error) {
        console.error((error as Error).message);
        process.exit(1);
    }
}

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
