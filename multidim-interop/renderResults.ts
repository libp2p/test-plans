import { promises as fs } from 'fs';
import { generateTable, load, markdownTable } from './src/lib'

// Read results.csv
export async function render() {
    const runs = load("results.csv")

    const regex = /(?<implA>.+)_x_(?<implB>.+)_\((?<options>.*)\)/
    const parsedRuns = runs.map(run => {
        const match = run.run_id.match(regex)
        if (!match || match.groups === undefined) {
            throw new Error(`Task ID ${run.run_id} does not match the expected format`);
        }
        return {
            ...run,
            implA: match.groups.implA,
            implB: match.groups.implB,
            options: match.groups.options.split(",").map(option => option.replace("_", " ").trim()),
        }
    })

    // Group by options
    const runsByOptions = parsedRuns.reduce((acc: { [key: string]: any }, run) => {
        acc[JSON.stringify(run.options)] = [...acc[JSON.stringify(run.options)] || [], run]
        return acc
    }, {})

    let outMd = ""

    for (const runGroup of Object.values(runsByOptions)) {
        outMd += `## Using: ${runGroup[0].options.join(", ")}\n`
        const table = generateTable(runGroup)
        outMd += markdownTable(table)
        outMd += "\n\n"
    }

    console.log(outMd)

}

render()

