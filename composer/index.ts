import toml from '@iarna/toml';
import * as csv from 'csv-parse/sync';
import fs from 'fs';
import process from 'process';

type ResultFile = [{ task_id: string, run_id: string, outcome: string, error: string }]

interface InstancesFile {
    custom?: InstanceDefinition
    master?: InstanceDefinition
    groups?: InstanceDefinition[]
}

interface InstanceDefinition {
    Id: string;
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
            columns: true, skip_empty_lines: true, delimiter: ','
        }) as any;
    } else {
        throw new Error(`Unknown file type: ${path}`);
    }
}

const save = (path: string, content: any) => {
    if (path.endsWith('.md')) {
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

const listAllVersions = (content: InstancesFile): InstanceDefinition[] => {
    return [content.custom, content.master, ...(content.groups || [])].filter(is);
}

const combinations = (versions: InstanceDefinition[]): RunDefinition[] => {
    const result: RunDefinition[] = [];

    for (let i = 0; i < versions.length; i++) {
        for (let j = i + 1; j < versions.length; j++) {

            const p1 = versions[i];
            const p2 = versions[j];

            const run: RunDefinition = {
                Id: `${p1.Id} x ${p2.Id}`,
                test_params: {
                    "iterations": "1",
                },
                groups: [
                    {
                        Id: p1.Id,
                        instances: { count: 1 }
                    },
                    {
                        Id: p2.Id,
                        instances: { count: 1 }
                    }
                ]
            }

            result.push(run);
        }
    }
    return result;
}

function generateTable(results: ResultFile, combinations: CombinationFile): string[][] {
    const instanceIds = combinations.instances.map(x => x.Id)

    const runIdToInstances = combinations.runs.reduce((acc, x) => {
        return { ...acc, [x.Id]: x.groups.map(g => g.Id) }
    }, {} as { [key: string]: string[] });

    const header = [" ", ...instanceIds];
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
        const otherIndex = instanceIds.indexOf(instance2);

        const url = encodeURIComponent(runId);

        const outcome = result.outcome === 'success' ? ':green_circle:' : ':red_circle:';
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

        const content: CombinationFile = { runs, instances: allVersions };
        save(outputPath, content);

        console.log(`Loaded ${allVersions.length} versions and generated ${runs.length} runs saved to ${outputPath}`);
    }
    else if (command === 'export-results') {
        // libp2p maintainers provide this

        // go templates + html might be a better approach here.
        const [inputPath, outputPath] = rest;

        const results = load<ResultFile>(inputPath);
        const combinations = load<CombinationFile>(combinationsPath);

        const table = generateTable(results, combinations)
        const content = markdownTable(table);
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
