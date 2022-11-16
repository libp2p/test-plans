import fs from 'fs';
import process from 'process';
import toml from '@iarna/toml';
import { spawn } from 'child_process';
import * as csv from 'csv-parse/sync';

type ResultFile = [{ run_index: number, run_id: string, status: string }]

interface InstancesFile {
    custom?: InstanceDefinition
    master?: InstanceDefinition
    groups?: InstanceDefinition[]
}

interface InstanceDefinition {
    Id: string;
    SupportedTransports: string[];
    [key: string]: unknown;
}

interface CompositionFile {
    groups: CompositionGroup[]
}

interface CompositionGroup {
    id: string;
    run?: {
        artifact?: string
    }
}

interface CombinationFile {
    runs: RunDefinition[];
    instances: InstanceDefinition[];
}

interface RunDefinition {
    Id: string;
    transport: string,
    test_params?: { [key: string]: (string | number) };
    groups: RunInstanceDefintion[]
}


interface RunInstanceDefintion {
    Id: string;
    instances: { count: number };
    test_params?: { [key: string]: (string | number) };
}

const is = <T>(x: undefined | T): x is T => {
    return x !== undefined;
}

const load = <T>(path: string): T => {
    // TODO: typecheck outputs
    if (path.endsWith('.json')) {
        return JSON.parse(fs.readFileSync(path, 'utf8'));
    } else if (path.endsWith('.toml')) {
        return toml.parse(fs.readFileSync(path, 'utf8')) as any;
    } else if (path.endsWith('.csv')) {
        return csv.parse(fs.readFileSync(path, 'utf8'), {
            columns: true, skip_empty_lines: true, delimiter: ';'
        }) as any;
    } else {
        throw new Error(`Unknown file type: ${path}`);
    }
}

const save = (path: string, content: any) => {
    if (path.endsWith('.md') || path.endsWith('.html')) {
        fs.writeFileSync(path, content);
    }
    else if (path.endsWith('.json')) {
        return fs.writeFileSync(path, JSON.stringify(content, null, 2));
    } else if (path.endsWith('.toml')) {
        return fs.writeFileSync(path, toml.stringify(content));
    } else {
        throw new Error(`Unknown file type: ${path}`);
    }
}

function crossMulTransport(base_id: InstanceDefinition): InstanceDefinition[] {
    const oned : InstanceDefinition[] = base_id.SupportedTransports.map((t: String) => {
            return {
                ...base_id,
                'Id': `${base_id.Id}.${t}`,
                'transport': t,
            };
        }
    );
    return oned;
}
function crossMulTransports(base_ids: InstanceDefinition[]): InstanceDefinition[] {
    return base_ids.map(crossMulTransport).flat();
}

function markdownTable(table: string[][]): string {
    return table.map((row, id) => {
        const r = '| ' + row.map(x => {
            return x.replace('|', '\\|')
        }).join(' | ') + ' |'

        if (id === 0) {
            return r + '\n' + '| ' + row.map(x => {
                return x.replace(/./g, '-')
            }).join(' | ') + ' |'
        } else {
            return r
        }


    }).join('\n')
}

function versionString(instance: InstanceDefinition): string {
    for ( let k of ['Version', 'Selector', 'Id'] ) {
        // console.log('looking for version as',k);
        // console.log(instance,instance[k]);
        if (instance[k]) {
            return instance[k] as string;
        }
    }
    return instance.Id;
}

function htmlTable(results: ResultFile, combinations: CombinationFile): string {
    const runIdToInstanceIds = combinations.runs.reduce((acc, x) => {
            return { ...acc, [x.Id]: x.groups.map(g => g.Id) }
        }, {} as { [key: string]: string[] });
    const instanceIdToInstance = new Map(combinations.instances.map(x => [x.Id, x]));
    let html = `<html>
<body>
<table border=1>
    <tbody>
        <tr>
            <td>Test case</td>
            <td colspan="3"><strong>Source Host</strong></td>
            <td rowspan="2">Run <p dir="auto">Test</p></td>
            <td colspan="3"><strong>Destination Host</strong></td>
            <td>Expected Res</td>
        </tr>
        <tr>
            <td></td>
            <td>Imp</td>
            <td>Ver</td>
            <td>Trans</td>
            <td>Imp</td>
            <td>Ver</td>
            <td>Trans</td>
            <td>RTT</td>
            <td>Status</td>
        </tr>
`;
    for ( const i in results ) {
        const one_based = parseInt(i) + 1;
        const result = results[parseInt(i)];
        const runId = result.run_id;
        let runParts = runId.split(':');
        console.log('runId',runId,'->',runParts);
        let transport = runParts.pop();
        if (!transport) {
            continue;
        }
        transport = transport.trim();
        console.log(transport);
        const [instanceLeft,instanceRight] = runIdToInstanceIds[runId];
        const l = instanceIdToInstance.get(instanceLeft );
        const r = instanceIdToInstance.get(instanceRight);
        if ( l && r ) {
            const lv = versionString(l);
            console.log('lv=',lv);
            const rv = versionString(r);
            console.log('rv=',rv);
            html += `
            <tr>
                <td>${one_based}</td>
                <td>${l.Implementation}</td>
                <td>${lv}</td>
                <td>${transport}</td>
                <td>X</td>
                <td>${r.Implementation}</td>
                <td>${rv}</td>
                <td>${transport}</td>
                <td>rtt</td>
                <td>${result.status}</td>
            </tr>
            `;
        } else {
            html += '<tr><td colspan=9>error</td></tr>';
        }
    }
    html += `
    </tbody>
</table>
</body>
</html>`;
    return html;
}

const listAllVersions = (content: InstancesFile): InstanceDefinition[] => {
    return [content.custom, content.master, ...(content.groups || [])].filter(is);
}

const callTestground = (testRunId: number, raw_args: string[]): Promise<void> => {
    const args = raw_args.map(x => {
        // replace the string __TEST_RUN_ID__ in x with the actual test run id.
        return x.replace('__TEST_RUN_ID__', testRunId.toString());
    })

    return new Promise((resolve, reject) => {
        const env = {
            ...process.env,
            TestRunId: `${testRunId}`
        }
        const tg = spawn("testground", args, {
            env
        });

        tg.stdout.on("data", (data: unknown) => {
            console.log(`stdout: ${data}`);
        });

        tg.stderr.on("data", (data: unknown) => {
            console.log(`stderr: ${data}`);
        });

        tg.on('error', (error: unknown) => {
            console.log(`error: ${error}`);
            reject(error);
        });

        tg.on("close", (code: number) => {
            console.log(`child process exited with code ${code}`);
            if (code === 0) {
                resolve();
            }
            reject(new Error("Testground failed"));
        });
    });
}

const combinations = (versions: InstanceDefinition[]): RunDefinition[] => {
    const result: RunDefinition[] = [];

    for (let i = 0; i < versions.length; i++) {
        for (let j = i + 1; j < versions.length; j++) {

            const p1 = versions[i];
            const p2 = versions[j];

            for (let transport of p1.SupportedTransports ) {
                if ( !p2.SupportedTransports.includes(transport) ) {
                    continue;
                }
                const run: RunDefinition = {
                    Id: `${p1.Id} x ${p2.Id} : ${transport}`,
                    transport: transport,
                    groups: [
                        {
                            Id: `${p1.Id}.${transport}`,
                            instances: { count: 1 },
                            test_params: {transport: transport},
                        },
                        {
                            Id: `${p2.Id}.${transport}`,
                            instances: { count: 1 },
                            test_params: {transport: transport},
                        }
                    ]
                }

                result.push(run);
            }
        }
    }
    return result;
}

function generateTable(results: ResultFile, combinations: CombinationFile): string[][] {
    const instanceId_Transport_combos = combinations.instances.map(x => x.SupportedTransports.map(t => `${x.Id}/${t}`)).flat()
    const instanceIds = combinations.instances.map(x => x.Id)

    const runIdToInstances = combinations.runs.reduce((acc, x) => {
        return { ...acc, [x.Id]: x.groups.map(g => g.Id) }
    }, {} as { [key: string]: string[] });

    const header = [" ", ...instanceId_Transport_combos];
    const table = [header, ...instanceIds.map(instanceId => {
        const row = instanceIds.map(otherInstanceId => {
            return ':white_circle:';
        });
        return [instanceId, ...row];
    })]

    for (const result of results) {
        const runId = result.run_id;
        const instances = runIdToInstances[runId];

        const [instance1, instance2] = instances;
        const index = instanceIds.indexOf(instance1);
        const otherIndex = instanceId_Transport_combos.indexOf(instance2);

        const url = encodeURIComponent(runId);

        const outcome = result.status === 'pass' ? ':green_circle:' : ':red_circle:';
        const cell = `[${outcome}](#${url})`

        table[index + 1][otherIndex + 1] = cell;
        table[otherIndex + 1][index + 1] = cell;
    }

    return table;
}


const main = async () => {
    const args: string[] = process.argv.slice(2);
    const [command, ...rest] = args;

    const combinationsPath = './demo/combinations.toml'

    if (command === 'combine') {
        // libp2p maintainers provide this

        // go templates might be enough to implement this function, but we'd
        // rather write code that we can extend (e.g. add more parameters, add rtts computation).
        const [outputPath, ...inputs] = rest;

        const resources = inputs.map(x => listAllVersions(load<InstancesFile>(x)));
        const allVersions = resources.flat()

        const runs = combinations(allVersions);

        const content: CombinationFile = { runs, instances: crossMulTransports(allVersions) };
        save(outputPath, content);

        console.log(`Loaded ${allVersions.length} versions and generated ${runs.length} runs saved to ${outputPath}`);
    }
    else if (command === 'export-results') {
        // libp2p maintainers provide this

        // go templates + html might be a better approach here.
        const [inputPath, outputPath] = rest;

        const results = load<ResultFile>(inputPath);
        const combinations = load<CombinationFile>(combinationsPath);

        // const table = generateTable(results, combinations)
        // const content = markdownTable(table);
        const content = htmlTable(results, combinations);
        save(outputPath, content);
    }
    else if (command === 'extract-artifacts') {
        // testground might provide this function
        const [outputPath, input] = rest;

        const composition = load<CompositionFile>(input)
        const artifacts: { [key: string]: string } = {};
        composition.groups.forEach(group => {
            const artifact = group?.run?.artifact

            if (artifact) {
                artifacts[group.id] = artifact
            }
        })
        save(outputPath, artifacts);
    }
    else if (command === 'foreach') {
        // testground should provide an equivalent to this function (see the README)
        const [outputPath, ...tgArgs] = rest;

        const runs = load<CombinationFile>(combinationsPath).runs;

        // TODO: what is the output we want for this matrix?
        fs.writeFileSync(outputPath, 'run_index;run_id;status\n');

        for (let i = 0; i < runs.length; i++) {
            // We WANT sequential run here.
            const run = runs[i];

            try {
                await callTestground(i, tgArgs);
                fs.appendFileSync(outputPath, `${i};${run.Id};pass\n`)
            } catch (error) {
                fs.appendFileSync(outputPath, `${i};${run.Id};fail\n`)
            }
        }
    } else {
        throw new Error(`Unknown command: ${command}`);
    }
}

main()
    .then(() => process.exit(0))
    .catch(err => {
        console.error(err);
        process.exit(1);
    })
