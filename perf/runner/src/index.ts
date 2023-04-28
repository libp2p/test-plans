import { execSync } from 'child_process';
import { versions } from './versions';
import yargs from 'yargs';
import fs from 'fs';
import { BenchmarkResults, Benchmark, Result } from './benchmark-result-type';

async function main(clientPublicIP: string, serverPublicIP: string) {
    for (const version of versions) {
        transferDockerImage(serverPublicIP, version.containerImageID);
        transferDockerImage(clientPublicIP, version.containerImageID);
    }

    const benchmarkResults: BenchmarkResults = {
        benchmarks: [
            runBenchmarkAcrossVersions({
                name: "Single Connection throughput – Upload 100 MiB",
                clientPublicIP,
                serverPublicIP,
                uploadBytes: 100 << 20,
                downloadBytes: 0,
                unit: "bit/s",
                iterations: 1,
            }),
            runBenchmarkAcrossVersions({
                name: "Single Connection throughput – Download 100 MiB",
                clientPublicIP,
                serverPublicIP,
                uploadBytes: 0,
                downloadBytes: 100 << 20,
                unit: "bit/s",
                iterations: 1,
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

        // The `if` is a hack for zig.
        if (version.serverAddress == undefined) {
            console.error(`=== Starting ${version.id} server.`);
            let serverCMD: string
            if (version.implementation === "zig-libp2p") {
                // Hack!
                serverCMD = `ssh ec2-user@${args.serverPublicIP} 'docker stop $(docker ps -aq); docker run --init -d --restart always --network host ${version.containerImageID} --run-server'`;
            } else {
                serverCMD = `ssh ec2-user@${args.serverPublicIP} 'docker stop $(docker ps -aq); docker run --init -d --restart always --network host ${version.containerImageID} --run-server --secret-key-seed 0'`;
            }
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
    dockerImageId: string;
    transportStack: string,
    uploadBytes: number,
    downloadBytes: number,
    iterations: number,
}

interface Latencies {
    latencies: number[];
}


function runBenchmark(args: ArgsRunBenchmark): Latencies {
    console.error(`=== Starting ${args.transportStack} client.`);

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

    // TODO: Remove static --n-times.
    const binFlags = `--server-address ${serverAddress} --upload-bytes ${args.uploadBytes} --download-bytes ${args.downloadBytes} --n-times 1`
    const dockerCMD = `docker run --init --rm --network host ${args.dockerImageId} ${binFlags}`
    const cmd = `ssh ec2-user@${args.clientPublicIP} 'for i in {1..${args.iterations}}; do ${dockerCMD}; done'`

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

async function transferDockerImage(serverIp: string, imageSha256: string): Promise<void> {
    const imageName = `image-${imageSha256.slice(0, 12)}`;
    const tarballName = `${imageName}.tar`;

    // Save the Docker image as a tarball, transfer it using rsync, load it on the remote server, and clean up tarball files locally.
    console.error(`== Transferring Docker image ${imageSha256} to ${serverIp}`);
    execCommand(`docker save -o ${tarballName} ${imageSha256} &&
               rsync -avz --progress ./${tarballName} ec2-user@${serverIp}:/tmp/ &&
               ssh ec2-user@${serverIp} 'docker load -i /tmp/${tarballName}' &&
               rm ${tarballName}`);

    console.error(`=== Docker image ${imageSha256} transferred successfully to ${serverIp}`);
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
