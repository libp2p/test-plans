import { execSync } from 'child_process';
import { Version, versions } from './versions';
import yargs from 'yargs';
import fs from 'fs';
import { BenchmarkResults, Benchmark, Result, IperfResults, PingResults, ResultValue } from './benchmark-result-type';

async function main(clientPublicIP: string, serverPublicIP: string, iterations: number, testFilter: string[]) {
    console.error(`= Starting benchmark with ${iterations} iterations on implementations ${testFilter}`);
    const pings = runPing(clientPublicIP, serverPublicIP);
    const iperf = runIPerf(clientPublicIP, serverPublicIP);

    const versionsToRun = versions.filter(version => testFilter.includes('*') || testFilter.includes(version.implementation))

    const implsToBuild = Array.from(new Set(versionsToRun.map(v => v.implementation))).join(' ');

    copyAndBuildPerfImplementations(serverPublicIP, implsToBuild);
    copyAndBuildPerfImplementations(clientPublicIP, implsToBuild);

    const benchmarks = [
             runBenchmarkAcrossVersions({
                 name: "Single Connection throughput – Upload 100 MiB",
                 clientPublicIP,
                 serverPublicIP,
                 uploadBytes: 100 << 20,
                 downloadBytes: 0,
                 unit: "bit/s",
                 iterations,
             }, versionsToRun),
             runBenchmarkAcrossVersions({
                 name: "Single Connection throughput – Download 100 MiB",
                 clientPublicIP,
                 serverPublicIP,
                 uploadBytes: 0,
                 downloadBytes: 100 << 20,
                 unit: "bit/s",
                 iterations,
             }, versionsToRun),
             runBenchmarkAcrossVersions({
                 name: "Connection establishment + 1 byte round trip latencies",
                 clientPublicIP,
                 serverPublicIP,
                 uploadBytes: 1,
                 downloadBytes: 1,
                 unit: "s",
                 iterations: iterations * 10,
             }, versionsToRun),
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

function runPing(clientPublicIP: string, serverPublicIP: string): PingResults {
    console.error(`= run 100 pings from client to server`);

    const cmd = `ssh -o StrictHostKeyChecking=no ec2-user@${clientPublicIP} 'ping -c 100 ${serverPublicIP}'`;
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

function runIPerf(clientPublicIP: string, serverPublicIP: string): IperfResults {
    const iterations = 60;
    console.error(`= run ${iterations} iPerf TCP from client to server`);

    const killCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${serverPublicIP} 'kill $(cat pidfile); rm pidfile; rm server.log || true'`;
    const killSTDOUT = execCommand(killCMD);
    console.error(killSTDOUT);

    const serverCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${serverPublicIP} 'nohup iperf3 -s > server.log 2>&1 & echo \$! > pidfile '`;
    const serverSTDOUT = execCommand(serverCMD);
    console.error(serverSTDOUT);

    const cmd = `ssh -o StrictHostKeyChecking=no ec2-user@${clientPublicIP} 'iperf3 -c ${serverPublicIP} -b 25g -t ${iterations}'`;
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
    uploadBytes: number,
    downloadBytes: number,
    unit: "bit/s" | "s",
    iterations: number,
}

function runBenchmarkAcrossVersions(args: ArgsRunBenchmarkAcrossVersions, versionsToRun: Version[]): Benchmark {
    console.error(`= Benchmark ${args.name} on versions ${versionsToRun.map(v => v.implementation).join(', ')}`)

    const results: Result[] = [];

    for (const version of versionsToRun) {
        console.error(`== Version ${version.implementation}/${version.id}`)

        console.error(`=== Starting server ${version.implementation}/${version.id}`);

        const killCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.serverPublicIP} 'kill $(cat pidfile); rm pidfile; rm server.log || true'`;
        const killSTDOUT = execCommand(killCMD);
        console.error(killSTDOUT);

        const serverCMD = `ssh -o StrictHostKeyChecking=no ec2-user@${args.serverPublicIP} 'nohup ./impl/${version.implementation}/${version.id}/perf --run-server --server-address 0.0.0.0:4001 > server.log 2>&1 & echo \$! > pidfile '`;
        const serverSTDOUT = execCommand(serverCMD);
        console.error(serverSTDOUT);

        for (const transportStack of version.transportStacks) {
            const result = runClient({
                clientPublicIP: args.clientPublicIP,
                serverPublicIP: args.serverPublicIP,
                id: version.id,
                implementation: version.implementation,
                transportStack: transportStack,
                uploadBytes: args.uploadBytes,
                downloadBytes: args.downloadBytes,
                iterations: args.iterations,
            });

            results.push({
                result,
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
        parameters: {
            uploadBytes: args.uploadBytes,
            downloadBytes: args.downloadBytes,
        }
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

function runClient(args: ArgsRunBenchmark): ResultValue[] {
    console.error(`=== Starting client ${args.implementation}/${args.id}/${args.transportStack}`);

    const perfCMD = `./impl/${args.implementation}/${args.id}/perf --server-address ${args.serverPublicIP}:4001 --transport ${args.transportStack} --upload-bytes ${args.uploadBytes} --download-bytes ${args.downloadBytes}`
    const cmd = `ssh -o StrictHostKeyChecking=no ec2-user@${args.clientPublicIP} 'for i in {1..${args.iterations}}; do ${perfCMD}; done'`

    const stdout = execCommand(cmd);

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
        return stdout;
    } catch (error) {
        console.error((error as Error).message);
        process.exit(1);
    }
}

function copyAndBuildPerfImplementations(ip: string, impls: string) {
    console.error(`= Building implementations for ${impls} on ${ip}`);

    const stdout = execCommand(`rsync -avz --progress --filter=':- .gitignore' -e "ssh -o StrictHostKeyChecking=no" ../impl ec2-user@${ip}:/home/ec2-user`);
    console.error(stdout.toString());

    const stdout2 = execCommand(`ssh -o StrictHostKeyChecking=no ec2-user@${ip} 'cd impl && make ${impls}'`);
    console.error(stdout2.toString());
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
        'iterations': {
            type: 'number',
            default: 10,
            description: 'Number of iterations to run',
            demandOption: false,
        },
        'test-filter': {
            type: 'string',
            array: true,
            choices: ['js-libp2p', 'rust-libp2p', 'go-libp2p', 'https', 'quic-go', '*'],
            description: 'Filter tests to run, only the implementations here will be run, * for all',
            demandOption: false,
            default: '*'
        }
    })
    .command('help', 'Print usage information', yargs.help)
    .parseSync();

main(argv['client-public-ip'] as string, argv['server-public-ip'] as string, argv['iterations'] as number, argv['test-filter'] as string[]);
