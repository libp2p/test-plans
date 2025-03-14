import { execSync } from 'child_process';
import { Version, versions } from './versions';
import yargs from 'yargs';
import fs from 'fs';
import { BenchmarkResults, Benchmark, Result, IperfResults, PingResults, ResultValue } from './benchmark-result-type';

async function main(clientPublicIP: string, serverPublicIP: string, testing: boolean, testFilter: string[]) {
    const iterations = testing ? 1 : 10;
    const durationSecondsPerIteration = testing ? 5 : 20;
    const pingCount = testing ? 1 : 100;
    const iPerfIterations = testing ? 1 : 60;

    console.error(`= Starting benchmark with ${iterations} iterations on implementations ${testFilter}`);

    const pings = runPing(clientPublicIP, serverPublicIP, pingCount);
    const iperf = runIPerf(clientPublicIP, serverPublicIP, iPerfIterations);

    const versionsToRun = versions.filter(version => testFilter.includes('all') || testFilter.includes(version.implementation))

    const implsToBuild = Array.from(new Set(versionsToRun.map(v => v.implementation))).join(' ');

    copyAndBuildPerfImplementations(serverPublicIP, implsToBuild);
    copyAndBuildPerfImplementations(clientPublicIP, implsToBuild);

    const benchmarks = [
        await runBenchmarkAcrossVersions({
            name: "throughput/upload",
            clientPublicIP,
            serverPublicIP,
            uploadBytes: Number.MAX_SAFE_INTEGER,
            downloadBytes: 0,
            unit: "bit/s",
            iterations,
            durationSecondsPerIteration: durationSecondsPerIteration,
        }, versionsToRun),
        await runBenchmarkAcrossVersions({
            name: "throughput/download",
            clientPublicIP,
            serverPublicIP,
            uploadBytes: 0,
            downloadBytes: Number.MAX_SAFE_INTEGER,
            unit: "bit/s",
            iterations,
            durationSecondsPerIteration: durationSecondsPerIteration,
        }, versionsToRun),
        await runBenchmarkAcrossVersions({
            name: "Connection establishment + 1 byte round trip latencies",
            clientPublicIP,
            serverPublicIP,
            uploadBytes: 1,
            downloadBytes: 1,
            unit: "s",
            iterations: pingCount,
            durationSecondsPerIteration: Number.MAX_SAFE_INTEGER,
        }, versionsToRun),
    ];

    const benchmarkResults: BenchmarkResults = {
        benchmarks,
        pings,
        iperf
    };

    // Save results to benchmark-results.json
    fs.writeFileSync('./benchmark-results.json', JSON.stringify(benchmarkResults, null, 2));

    console.error("== done");
}

function runPing(clientPublicIP: string, serverPublicIP: string, pingCount: number): PingResults {
    console.error(`= run ${pingCount} pings from client to server`);

    const cmd = `ssh -o StrictHostKeyChecking=no ec2-user@${clientPublicIP} 'ping -c ${pingCount} ${serverPublicIP}'`;
    const stdout = execCommand(cmd).toString();

    // Extract the time from each ping
    const lines = stdout.split('\n');
    const times = lines
        .map(line => {
            const match = line.match(/time=(.*) ms/);
            return match ? parseFloat(match[1]) / 1000 : null; // Convert from ms to s
        })
        .filter((time): time is number => time !== null); // Remove any null values and ensure that array contains only numbers

    return { unit: "s", results: times }
}

function runIPerf(clientPublicIP: string, serverPublicIP: string, iPerfIterations: number): IperfResults {
    console.error(`= run ${iPerfIterations} iPerf TCP from client to server`);

    const killCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${serverPublicIP} 'kill $(cat pidfile); rm pidfile; rm server.log || true'`;
    const killSTDOUT = execCommand(killCMD);
    if (killSTDOUT) {
        console.error(killSTDOUT);
    }

    const serverCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${serverPublicIP} 'nohup iperf3 -s > server.log 2>&1 & echo \$! > pidfile '`;
    const serverSTDOUT = execCommand(serverCMD);
    if (serverSTDOUT) {
        console.error(serverSTDOUT);
    }

    const cmd = `ssh -o StrictHostKeyChecking=no ec2-user@${clientPublicIP} 'iperf3 -c ${serverPublicIP} -t ${iPerfIterations} -N'`;
    const stdout = execSync(cmd).toString();

    // Extract the bitrate from each relevant line
    const lines = stdout.split('\n');
    const bitrates = lines
        .map(line => {
            const match = line.match(/(\d+(?:\.\d+)?) (\w)bits\/sec/); // Matches and captures the number and unit before "bits/sec"
            if (match) {
                const value = parseFloat(match[1]);
                const unit = match[2];
                // Convert value to bits/sec
                const multiplier = unit === 'G' ? 1e9 : unit === 'M' ? 1e6 : unit === 'K' ? 1e3 : 1;
                return value * multiplier;
            }
            return null;
        })
        .filter((bitrate): bitrate is number => bitrate !== null); // Remove any null values

    return { unit: "bit/s", results: bitrates }
}

interface ArgsRunBenchmarkAcrossVersions {
    name: string,
    clientPublicIP: string;
    serverPublicIP: string;
    uploadBytes: number,
    downloadBytes: number,
    unit: "bit/s" | "s",
    iterations: number,
    durationSecondsPerIteration: number,
}

async function runBenchmarkAcrossVersions(args: ArgsRunBenchmarkAcrossVersions, versionsToRun: Version[]): Promise<Benchmark> {
    console.error(`= Benchmark ${args.name} on versions ${versionsToRun.map(v => v.implementation).join(', ')}`)

    const results: Result[] = [];

    for (const version of versionsToRun) {
        console.error(`== Version ${version.implementation}/${version.id}`)

        for (const transportStack of version.transports) {
            const killCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.serverPublicIP} 'kill $(cat pidfile); rm pidfile; rm server.log || true'`;
            const killSTDOUT = execCommand(killCMD);
            if (killSTDOUT) {
                console.error(killSTDOUT);
            }

            const transport = typeof transportStack === 'string' ? transportStack : transportStack.transport
            const encryption = typeof transportStack === 'string' ? undefined : transportStack.encryption

            console.error(`=== Starting server ${version.implementation}/${version.id}/${transport}${encryption ? `/${encryption}` : ''}`);
            const serverArgs = [
                `nohup ./impl/${version.implementation}/${version.id}/perf`,
                '--run-server',
                '--server-address 0.0.0.0:4001',
                // TODO: go and rust refuse to run with unknown cli args
                version.implementation === 'js-libp2p' ? `--transport ${transport}` : '',
                version.implementation === 'js-libp2p' && encryption ? `--encryption ${encryption}` : ''
            ]
            const serverCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.serverPublicIP} '${serverArgs.join(' ')} > server.log 2>&1 & echo \$! > pidfile '`;
            const serverSTDOUT = execCommand(serverCMD);
            if (serverSTDOUT) {
                console.error(serverSTDOUT);
            }

            const result = runClient({
                clientPublicIP: args.clientPublicIP,
                serverPublicIP: args.serverPublicIP,
                id: version.id,
                implementation: version.implementation,
                transport,
                encryption,
                uploadBytes: args.uploadBytes,
                downloadBytes: args.downloadBytes,
                iterations: args.iterations,
                durationSecondsPerIteration: args.durationSecondsPerIteration,
                serverMultiaddr: await waitForMultiaddr(args.serverPublicIP)
            });

            results.push({
                result,
                implementation: version.implementation,
                version: version.id,
                transportStack: typeof transportStack === 'string' ? transportStack : `${transportStack.transport}/${transportStack.encryption}`
            });
        }
    };

    return {
        name: args.name,
        unit: args.unit,
        results,
        parameters: {
            uploadBytes: args.uploadBytes,
            downloadBytes: args.downloadBytes,
        }
    };
}

interface ArgsRunBenchmark {
    clientPublicIP: string;
    serverPublicIP: string;
    serverMultiaddr?: string;
    id: string,
    implementation: string,
    transport: string,
    encryption?: string,
    uploadBytes: number,
    downloadBytes: number,
    iterations: number,
    durationSecondsPerIteration: number,
}

function runClient(args: ArgsRunBenchmark): ResultValue[] {
    console.error(`=== Starting client ${args.implementation}/${args.id}/${args.transport}${args.encryption ? `/${args.encryption}` : ''}`);

    const clientArgs = [
        `./impl/${args.implementation}/${args.id}/perf`,
        `--server-address ${args.serverPublicIP}:4001`,
        // TODO: go and rust refuse to run with unknown cli args
        args.implementation === 'js-libp2p' && args.serverMultiaddr ? `--server-multiaddr ${args.serverMultiaddr}` : '',
        args.implementation === 'js-libp2p' && args.encryption ? `--encryption ${args.encryption}` : '',
        `--transport ${args.transport}`,
        `--upload-bytes ${args.uploadBytes}`,
        `--download-bytes ${args.downloadBytes}`
    ]
    const cmd = clientArgs.join(' ')
    // Note 124 is timeout's exit code when timeout is hit which is not a failure here.
    const withTimeout = `timeout ${args.durationSecondsPerIteration}s ${cmd} || [ $? -eq 124 ]`
    const withForLoop = `for i in {1..${args.iterations}}; do ${withTimeout}; done`
    const withSSH = `ssh -o StrictHostKeyChecking=no ec2-user@${args.clientPublicIP} '${withForLoop}'`

    try {
        const stdout = execCommand(withSSH);

        const lines = stdout.toString().trim().split('\n');

        const combined: ResultValue[] = [];

        for (const line of lines) {
            const result = JSON.parse(line) as ResultValue;
            combined.push(result);
        }

        return combined;
    } catch (err) {
        console.error('=== Client failed, server logs:')
        console.error(getServerLogs(args.serverPublicIP))

        throw err
    }
}

function execCommand(cmd: string): string {
    try {
        const stdout = execSync(cmd, {
            encoding: 'utf8',
            stdio: [process.stdin, 'pipe', process.stderr],
        });
        return stdout.trim();
    } catch (error) {
        console.error((error as Error).message);

        throw error
    }
}

function copyAndBuildPerfImplementations(ip: string, impls: string) {
    console.error(`= Building implementations for ${impls} on ${ip}`);

    const stdout = execCommand(`rsync -avz --progress --filter=':- .gitignore' -e "ssh -o StrictHostKeyChecking=no" ../impl ec2-user@${ip}:/home/ec2-user`);
    console.error(stdout.toString());

    const stdout2 = execCommand(`ssh -o StrictHostKeyChecking=no ec2-user@${ip} 'cd impl && make ${impls}'`);
    console.error(stdout2.toString());
}

interface DeferredPromise<T> {
    promise: Promise<T>
    resolve(val: T): void
    reject(err?: Error): void
}

function defer <T = void> (): DeferredPromise<T> {
    let res: (val: T) => void = () => {}
    let rej: (err?: Error) => void = () => {}

    const p = new Promise<T>((resolve, reject) => {
        res = resolve
        rej = reject
    })

    return {
        promise: p,
        resolve: res,
        reject: rej
    }
}

/**
 * Attempts to parse a multiaddr from the output, otherwise returns the passed
 * host:port pair if passed.
 */
function waitForMultiaddr (serverPublicIP: string): Promise<string | undefined> {
    const deferred = defer<string | undefined>()
    const repeat = 10
    const delay = 1000

    Promise.resolve().then(async () => {
        let serverSTDOUT = ''

        for (let i = 0; i < repeat; i++) {
            serverSTDOUT = getServerLogs(serverPublicIP);

            if (serverSTDOUT.length > 0) {
                for (let line of serverSTDOUT.split('\n')) {
                    line = line.trim()

                    if (line.length === 0) {
                        continue
                    }

                    // does it look like a multiaddr?
                    if (line.includes('/p2p/')) {
                    deferred.resolve(line)
                    }
                }
            }

            // nothing found, wait a second before retrying
            await new Promise<void>((resolve) => {
                setTimeout(() => {
                    resolve()
                }, delay)
            })
        }

        // resolve if no multiaddr is printed into the logs
        deferred.resolve(undefined)
    })

    return deferred.promise
}

function getServerLogs (serverPublicIP: string): string {
    const serverCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${serverPublicIP} 'tail -n 100 server.log'`;
    return execCommand(serverCMD);
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
        'testing': {
            type: 'boolean',
            default: false,
            description: 'Run in testing mode',
            demandOption: false,
        },
        'test-filter': {
            type: 'string',
            array: true,
            choices: ['js-libp2p', 'rust-libp2p', 'go-libp2p', 'https', 'quic-go', 'all'],
            description: 'Filter tests to run, only the implementations here will be run. It defaults to all.',
            demandOption: false,
            default: ['all']
        }
    })
    .command('help', 'Print usage information', yargs.help)
    .parseSync();

main(argv['client-public-ip'] as string, argv['server-public-ip'] as string, argv['testing'] as boolean, argv['test-filter'] as string[]);
