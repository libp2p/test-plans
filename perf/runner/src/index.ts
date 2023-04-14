import { execSync } from 'child_process';
import { versions } from './versions';
import yargs from 'yargs';
import fs from 'fs';
import { BenchmarkResults, Benchmark, Result } from './benchmark-result-type';

async function main(clientPublicIP: string, serverPublicIP: string) {
    const benchmarkResults: BenchmarkResults = {
        benchmarks: [
            {
                name: "Single Connection throughput – Upload 10 MiB",
                unit: "s",
                results: runBenchmarkAcrossVersions({
                    clientPublicIP,
                    serverPublicIP,
                    uploadBytes: 10 * 1024 * 1024,
                    downloadBytes: 0,
                    nTimes: 1,
                }),
                comparisons: [],
            },
            {
                name: "Single Connection throughput – Download 10 MiB",
                unit: "s",
                results: runBenchmarkAcrossVersions({
                    clientPublicIP,
                    serverPublicIP,
                    uploadBytes: 0,
                    downloadBytes: 10 * 1024 * 1024,
                    nTimes: 1,
                }),
                comparisons: [],
            },
            {
                name: "Single Connection 1 byte round trip latency",
                unit: "s",
                results: runBenchmarkAcrossVersions({
                    clientPublicIP,
                    serverPublicIP,
                    uploadBytes: 1,
                    downloadBytes: 1,
                    nTimes: 10,
                }),
                comparisons: [],
            }
        ],
    };

    console.log(JSON.stringify(benchmarkResults, null, 2));

    // Save results to benchmark-results.json
    fs.writeFileSync('./benchmark-results.json', JSON.stringify(benchmarkResults, null, 2));
}

interface ArgsRunBenchmarkAcrossVersions {
    clientPublicIP: string;
    serverPublicIP: string;
    uploadBytes: number,
    downloadBytes: number,
    nTimes: number,
}

function runBenchmarkAcrossVersions(args: ArgsRunBenchmarkAcrossVersions): Result[] {
    const results: Result[] = [];
    for (const version of versions) {
        if (version.serverAddress == undefined) {
            console.error(`Starting ${version.id} server.`);
            const serverCMD = `ssh ec2-user@${args.serverPublicIP} 'docker stop $(docker ps -aq); docker run --init -d --restart always --network host --entrypoint /app/server ${version.containerImageID} --secret-key-seed 0'`;
            console.error(serverCMD);
            const serverSTDOUT = execCommand(serverCMD);
            console.error(serverSTDOUT);
        }

        for (const transportStack of version.transportStacks) {
            const latencies = runBenchmark({
                clientPublicIP: args.clientPublicIP,
                serverPublicIP: args.serverPublicIP,
                serverAddress: version.serverAddress,
                dockerImageId: version.containerImageID,
                transportStack: transportStack,
                uploadBytes: args.uploadBytes,
                downloadBytes: args.downloadBytes,
                nTimes: args.nTimes,
            });

            results.push({
                result: latencies.latencies,
                implementation: version.implementation,
                version: version.id,
                transportStack: transportStack,
            });
        }
    };

    return results;
}

interface ArgsRunBenchmark {
    clientPublicIP: string;
    serverPublicIP: string;
    serverAddress?: string;
    dockerImageId: string;
    transportStack: string,
    uploadBytes: number,
    downloadBytes: number,
    nTimes: number,
}

interface Latencies {
    latencies: number[];
}


function runBenchmark(args: ArgsRunBenchmark): Latencies {
    console.error(`Starting ${args.transportStack} client.`);

    let serverAddress = args.serverAddress;

    if (serverAddress == undefined) {
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
        serverAddress = serverAddress + "/p2p/12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN";
    }

    const binFlags = `--server-address ${serverAddress} --upload-bytes ${args.uploadBytes} --download-bytes ${args.downloadBytes} --n-times ${args.nTimes}`
    // TODO Take docker hub repository from version.ts
    const dockerCMD = `docker run --init --rm --network host ${args.dockerImageId} ${binFlags}`
    const cmd = `ssh ec2-user@${args.clientPublicIP} ${dockerCMD}`;
    console.log("Running command:", cmd);

    const stdout = execCommand(cmd);
    console.log("Stdout from client:", stdout.toString(), JSON.parse(stdout.toString()));
    const parsedStdout = JSON.parse(stdout.toString());

    let latencies: Latencies
    if (Array.isArray(parsedStdout)) {
        latencies = { latencies: parsedStdout }
    } else {
        latencies = parsedStdout
    }

    return latencies;
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
