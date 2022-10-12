import fs from 'fs';
import process from 'process';
import toml from '@iarna/toml';
import { spawn } from 'child_process';

interface IVersionInfo {
    Id: string;
}

interface IVersionFile {
    custom: IVersionInfo
    master: IVersionInfo
    groups: IVersionInfo[]
}

interface ICompositionGroup {
    id: string;
    run?: {
        artifact?: string
    }
}

interface ICompositionFile {
    groups: ICompositionGroup[]
}

interface IRunParams {
    Id: string;
}

interface IRunsFile {
    TestRuns: IRunParams[][];
    TestVersions: IVersionInfo[];
}

const allVersions = (content: IVersionFile): IVersionInfo[] => {
    return [content.custom, content.master, ...content.groups].filter(x => !!x);
}

const load = <T>(path: string): T => {
    // TODO: typecheck outputs
    if (path.endsWith('.json')) {
        return JSON.parse(fs.readFileSync(path, 'utf8'));
    } else if (path.endsWith('.toml')) {
        return toml.parse(fs.readFileSync(path, 'utf8')) as any;
    } else {
        throw new Error(`Unknown file type: ${path}`);
    }
}

const save = (path: string, content: any) => {
    if (path.endsWith('.json')) {
        return fs.writeFileSync(path, JSON.stringify(content, null, 2));
    } else if (path.endsWith('.toml')) {
        return fs.writeFileSync(path, toml.stringify(content));
    } else {
        throw new Error(`Unknown file type: ${path}`);
    }
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

const combinations = (versions: IVersionInfo[]): IRunParams[][] => {
    const result: IVersionInfo[][] = [];

    for (let i = 0; i < versions.length; i++) {
        for (let j = i + 1; j < versions.length; j++) {

            const p1 = versions[i];
            const p2 = versions[j];
            result.push([{ Id: p1.Id }, { Id: p2.Id }]);
        }
    }
    return result;
}

const main = async () => {
    const args = process.argv.slice(2);
    const [command, ...rest] = args;
    const combinationsPath = './partialized/combinations.toml'
    const buildArtifactsPath = './partialized/builds-artifacts.toml'
    const artifactsPath = './partialized/artifacts.toml'

    if (command === 'combine') {
        const rust = allVersions(load<IVersionFile>('./rust.toml'))
        const go = allVersions(load<IVersionFile>('./go.toml'))

        const versions = [...rust, ...go]

        const runs = combinations([...rust, ...go]);
        const content: IRunsFile = { TestRuns: runs, TestVersions: versions };
        save(combinationsPath, content);
        console.log(`Generated ${runs.length} runs saved to ${combinationsPath}`);
    }
    else if (command === 'gather-artifacts') {
        const composition = load<ICompositionFile>(buildArtifactsPath)
        const artifacts: { [key: string]: string } = {};
        composition.groups.forEach(group => {
            const artifact = group?.run?.artifact

            if (artifact) {
                artifacts[group.id] = artifact
            }
        })
        save(artifactsPath, artifacts);
    }
    else if (command === 'foreach') {
        const runs = load<IRunsFile>(combinationsPath).TestRuns;
        const outputPath = './results.txt'
        fs.writeFileSync(outputPath, 'run_id;status;\n');

        for (let i = 0; i < runs.length; i++) {
            // We WANT sequential run here.
            try {
                await callTestground(i, rest);
                fs.appendFileSync(outputPath, `${i};pass;\n`)
            } catch (error) {
                fs.appendFileSync(outputPath, `${i};fail;\n`)
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