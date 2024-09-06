import { execSync, exec, ChildProcess } from 'child_process';
import { PLATFORM, versions } from './versions';
import yargs from 'yargs';
import fs from 'fs';
import type { BenchmarkResults, Benchmark, Result, IperfResults, PingResults, ResultValue } from './benchmark-result-type';

async function main(clientPublicIP: string, serverPublicIP: string, relayPublicIP: string, testing: boolean) {
    testing = true
    const pings = runPing(clientPublicIP, serverPublicIP, relayPublicIP, testing);
    const iperf = runIPerf(clientPublicIP, serverPublicIP, relayPublicIP, testing);

    await Promise.all([
        copyAndBuildPerfImplementations(relayPublicIP),
        copyAndBuildPerfImplementations(serverPublicIP),
        copyAndBuildPerfImplementations(clientPublicIP)
    ])

    const benchmarks = [
        await runBenchmarkAcrossVersions({
            name: "throughput/upload",
            clientPublicIP,
            serverPublicIP,
            relayPublicIP,
            uploadBytes: Number.MAX_SAFE_INTEGER,
            downloadBytes: 0,
            unit: "bit/s",
            iterations: testing ? 1 : 10,
            durationSecondsPerIteration: testing ? 5 : 20,
        }),
        await runBenchmarkAcrossVersions({
            name: "throughput/download",
            clientPublicIP,
            serverPublicIP,
            relayPublicIP,
            uploadBytes: 0,
            downloadBytes: Number.MAX_SAFE_INTEGER,
            unit: "bit/s",
            iterations: testing ? 1 : 10,
            durationSecondsPerIteration: testing ? 5 : 20,
        }),
        await runBenchmarkAcrossVersions({
            name: "Connection establishment + 1 byte round trip latencies",
            clientPublicIP,
            serverPublicIP,
            relayPublicIP,
            uploadBytes: 1,
            downloadBytes: 1,
            unit: "s",
            iterations: testing ? 1 : 100,
            durationSecondsPerIteration: Number.MAX_SAFE_INTEGER,
        }),
    ];

    const benchmarkResults: BenchmarkResults = {
        benchmarks,
        pings,
        iperf,
    };

    // Save results to benchmark-results.json
    fs.writeFileSync('./benchmark-results.json', JSON.stringify(benchmarkResults, null, 2));

    console.error("== done");
}

function runPing(clientPublicIP: string, serverPublicIP: string, relayPublicIP: string, testing: boolean): PingResults {
    const pingCount = testing ? 1 : 100;
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

function runIPerf(clientPublicIP: string, serverPublicIP: string, relayPublicIP: string, testing: boolean): IperfResults {
    const iPerfIterations = testing ? 1 : 60;
    console.error(`= run ${iPerfIterations} iPerf TCP from client to server`);

    const killCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${serverPublicIP} 'kill $(cat pidfile); rm pidfile; rm server.log || true'`;
    const killSTDOUT = execCommand(killCMD);
    console.error(killSTDOUT);

    const serverCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${serverPublicIP} 'nohup iperf3 -s > server.log 2>&1 & echo \$! > pidfile '`;
    const serverSTDOUT = execCommand(serverCMD);
    console.error(serverSTDOUT);

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

    return { unit: "bit/s", results:  bitrates}
}

interface ArgsRunBenchmarkAcrossVersions {
    name: string,
    clientPublicIP: string;
    serverPublicIP: string;
    relayPublicIP: string;
    uploadBytes: number,
    downloadBytes: number,
    unit: "bit/s" | "s",
    iterations: number,
    durationSecondsPerIteration: number,
}

async function runBenchmarkAcrossVersions(args: ArgsRunBenchmarkAcrossVersions): Promise<Benchmark> {
    console.error(`= Benchmark ${args.name}`)

    const results: Result[] = [];
    let relayAddress: string | undefined
    let listenerAddress: string

    for (const version of versions) {
        console.error(`== Version ${version.implementation}/${version.id}`)

        let relayProc: ChildProcess | undefined

        if (version.relay === true) {
            console.error(`=== Starting relay ${version.implementation}/${version.id}`);

            const relayKillCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.relayPublicIP} 'kill $(cat pidfile); rm pidfile || true'`;
            const relayKillSTDOUT = execCommand(relayKillCMD);
            console.error(relayKillSTDOUT);

            const relayCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.relayPublicIP} 'nohup ./impl/${version.implementation}/${version.id}/perf --role relay --external-ip ${args.relayPublicIP} --listen-port 8001 & echo \$! > pidfile '`;
            const { proc, promise } = await waitForMultiaddr('Relay', relayCMD)
            relayProc = proc
            relayAddress = await promise
            console.error('Relay listening on', relayAddress);
        }

        for (const transportStack of version.transportStacks) {
            console.error(`=== Starting ${transportStack} listener ${version.implementation}/${version.id}`);

            const killCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.serverPublicIP} 'kill $(cat pidfile); rm pidfile || true'`;
            const killSTDOUT = execCommand(killCMD);
            console.error(killSTDOUT);

            const listenerCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.serverPublicIP} 'nohup ./impl/${version.implementation}/${version.id}/perf --role listener --external-ip ${args.serverPublicIP} --listen-port 4001 --transport ${transportStack}${version.server != null ? ` --platform ${version.server}` : ''}${relayAddress ? ` --relay-address ${relayAddress}` : ''} & echo \$! > pidfile '`;
            const { proc, promise } = await waitForMultiaddr('Listener', listenerCMD)
            const listenerProc = proc
            listenerAddress = await promise

            console.error('Listener listening on', listenerAddress);

            const result = runClient({
                ...args,
                ...version,
                transportStack,
                listenerAddress
            });

            results.push({
                result,
                implementation: version.implementation,
                version: version.id,
                transportStack: transportStack,
            });

            listenerProc.kill()
        }

        relayProc?.kill()
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
    id: string,
    clientPublicIP: string
    implementation: string
    transportStack: string
    uploadBytes: number
    downloadBytes: number
    iterations: number
    durationSecondsPerIteration: number
    client?: PLATFORM
    listenerAddress: string
}

function runClient(args: ArgsRunBenchmark): ResultValue[] {
    console.error(`=== Starting client ${args.implementation}/${args.id}/${args.transportStack}`);

    const cmd = `./impl/${args.implementation}/${args.id}/perf --role dialer --listener-address ${args.listenerAddress} --transport ${args.transportStack} --upload-bytes ${args.uploadBytes} --download-bytes ${args.downloadBytes} ${args.client != null ? `--platform ${args.client}` : ''}`
    // Note 124 is timeout's exit code when timeout is hit which is not a failure here.
    const withTimeout = `timeout ${args.durationSecondsPerIteration}s ${cmd} || [ $? -eq 124 ]`
    const withForLoop = `for i in {1..${args.iterations}}; do ${withTimeout}; done`
    const withSSH = `ssh -o StrictHostKeyChecking=no ec2-user@${args.clientPublicIP} '${withForLoop}'`

    const stdout = execCommand(withSSH);

    console.error('RESULT')
    console.error(stdout)

    const lines = stdout.toString().trim().split('\n');

    const combined: ResultValue[]= [];

    for (const line of lines) {
        const result = JSON.parse(line) as ResultValue;
        combined.push(result);
    }

    return combined;
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
        process.exit(1);
    }
}

async function copyAndBuildPerfImplementations(ip: string): Promise<void> {
    console.error(`= Building implementations on ${ip}`);

    const rsyncDeferred = defer()
    let rsyncStdout = ''
    const rsyncProc = exec(`rsync -avz --progress --filter=':- .gitignore' -e "ssh -o StrictHostKeyChecking=no" ../impl ec2-user@${ip}:/home/ec2-user`);
    rsyncProc.stdout?.on('data', buf => {
        rsyncStdout += buf.toString()
    })
    rsyncProc.on('exit', () => {
        rsyncDeferred.resolve()
    })
    rsyncProc.on('error', err => {
        rsyncDeferred.reject(err)
    })
    await rsyncDeferred.promise
    console.error(rsyncStdout)

    const makeDeferred = defer()
    let makeStdout = ''
    const makeProc = exec(`ssh -o StrictHostKeyChecking=no ec2-user@${ip} 'cd impl && make'`);
    makeProc.stdout?.on('data', buf => {
        makeStdout += buf.toString()
    })
    makeProc.on('exit', () => {
        makeDeferred.resolve()
    })
    makeProc.on('error', err => {
        makeDeferred.reject(err)
    })
    await makeDeferred.promise
    console.error(makeStdout)
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
        'relay-public-ip': {
            type: 'string',
            demandOption: true,
            description: 'Relay public IP address',
        },
        'testing': {
            type: 'boolean',
            default: false,
            description: 'Run in testing mode',
            demandOption: false,
        }
    })
    .command('help', 'Print usage information', yargs.help)
    .parseSync();

main(argv['client-public-ip'] as string, argv['server-public-ip'] as string, argv['relay-public-ip'] as string, argv['testing'] as boolean);

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

function waitForMultiaddr (name: string, cmd: string): { proc: ChildProcess, promise: Promise<string> } {
    const deferred = defer<string>()
    const proc = exec(cmd)
    proc.stdout?.on('data', (buf) => {
        console.error(`[${name} STDOUT]`, buf.toString())

        const str = buf.toString('utf8').trim()

        // does it look like a multiaddr?
        if (str.includes('/p2p/')) {
            deferred.resolve(str)
        }
    })
    proc.stderr?.on('data', (buf) => {
        console.error(`[${name} STDERR]`, buf.toString())
    })
    proc.on('close', () => {
        deferred.reject(new Error(`${name} exited without listening on an address`))
    })
    proc.on('error', (err) => {
        deferred.reject(err)
    })

    return {
        proc,
        promise: deferred.promise
    }
}
