import sqlite3 from "sqlite3";
import { open } from "sqlite";
import { promisify } from "util";
import toml from "@iarna/toml";
import yargs from "yargs";

const execFile = promisify(require("node:child_process").execFile);
const writeFile = promisify(require("node:fs").writeFile);
const unlink = promisify(require("node:fs").unlink);

const DB = "combinations.db";
// Set the builder as docker generic for every group.
const BUILDER = "docker:generic";

// Command line arguments.
const argv = yargs(process.argv.slice(2))
    .options({
        "rust-git-ref": { type: "string", demandOption: false },
        "rust-git-target": { type: "string", demandOption: false },
        "go-git-ref": { type: "string", demandOption: false },
        "go-git-target": { type: "string", demandOption: false },
        total_instances: { type: "number", demandOption: true },
    })
    .parseSync();

// TOML schema to generate.
class Instance {
    constructor(public count: number) {}
}

class BuildArgs {
    VERSION: string;
    GIT_REF?: string;
    GIT_TARGET?: string;

    constructor(
        version: string,
        rustGitRef?: string,
        rustGitTarget?: string,
        goGitRef?: string,
        goGitTarget?: string
    ) {
        this.VERSION = version;

        if (version.includes("master")) {
            if (version.includes("rust")) {
                this.GIT_REF = rustGitRef;
                this.GIT_TARGET = rustGitTarget;
            }
            if (version.includes("go")) {
                this.GIT_REF = goGitRef;
                this.GIT_TARGET = goGitTarget;
            }
        }
    }
}

class BuildConfig {
    constructor(public build_args: BuildArgs) {}
}

class TestParams {
    constructor(
        public transport: string,
        public muxer: string,
    ){}
}

class Group {
    constructor(
        public id: string,
        public builder: string,
        public instances: Instance,
        public build_config: BuildConfig,
        public test_params: TestParams
    ) {}
}

class Run {
    constructor(public id: string, public groups: Group[]) {}
}

class Global {
    constructor(
        public plan: string,
        public plan_case: string,
        public total_instances: number
    ) {}
}

class Composition {
    constructor(public global: Global, public runs: Run[]) {}
}

async function main() {
    sqlite3.verbose();

    // Call sqlite to process the csv resource files and generate a database.
    // We call the sqlite process instead of doing it here cause
    // the dot commands are interpreted by the sqlite cli tool not sqlite itself,
    // and it is a lot faster parsing the csv's.
    const { stdout, stderr } = await execFile("sqlite3", [
        DB,
        ".mode csv",
        ".import transports.csv transports",
        ".import muxers.csv muxers",
    ]);
    if (stderr != "") {
        throw new Error(`Could not parse csv resources: ${stderr}`);
    }

    const db = await open({
        filename: DB,
        driver: sqlite3.Database,
    });

    // Generate the testing combinations by SELECT'ing from both transports
    // and muxers tables the distinct combinations where the transport and the muxer
    // of the different libp2p implementations match.
    const queryResults =
        await db.all(`SELECT DISTINCT a.id as id1, b.id as id2, a.transport, ma.muxer
                     FROM transports a, transports b, muxers ma, muxers mb
                     WHERE a.id != b.id
                     AND a.transport == b.transport
                     AND a.id == ma.id
                     AND b.id == mb.id
                     AND ma.muxer == mb.muxer;`);
    await db.close();

    let global = new Global(
        "multidimensional-testing",
        "multidimensional",
        argv.total_instances
    );
    let composition = new Composition(global, []);

    for (let row of queryResults) {
        // Instance count is hardcoded to 1 for now.
        let instance = new Instance(1);

        let test_params = new TestParams(row.transport, row.muxer);
        let build_args1 = new BuildArgs(
            row.id1,
            argv.rustGitRef,
            argv.rustGitTarget,
            argv.goGitRef,
            argv.goGitTarget
        );

        let build_config1 = new BuildConfig(build_args1);
        let group1 = new Group(row.id1, BUILDER, instance, build_config1, test_params);

        let build_args2 = new BuildArgs(
            row.id2,
            argv.rustGitRef,
            argv.rustGitTarget,
            argv.goGitRef,
            argv.goGitTarget
        );
        let build_config2 = new BuildConfig(build_args2);
        let group2 = new Group(row.id2, BUILDER, instance, build_config2, test_params);

        let run = new Run(
            `${row.id1} x ${row.id2} x ${row.transport} x ${row.muxer}`,
            [group1, group2]
        );

        composition.runs.push(run);
    }

    // Write the TOML file and remove the database file to avoid corrupting
    // future runs.
    await writeFile("composition.toml", toml.stringify(composition as any));
    await unlink(DB);
}

main()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
