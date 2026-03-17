import fs from 'fs'
import { generateTable, load, makeDefaultCellRender, markdownTable } from './src/lib'

function loadKnownErrorsFile(): RegExp | null {
    if (process.argv.includes("--ignore-known-errors-file")) {
        return null
    }
    const path = __dirname + "/knownErrors.json"
    if (!fs.existsSync(path)) {
        return null
    }
    const patterns: string[] = JSON.parse(fs.readFileSync(path, "utf8"))
    if (patterns.length === 0) {
        return null
    }
    return new RegExp(patterns.join("|"))
}

function parseKnownErrors(): RegExp | null {
    const flagIndex = process.argv.indexOf("--known-errors")
    if (flagIndex === -1 || flagIndex + 1 >= process.argv.length) {
        return loadKnownErrorsFile()
    }
    const flagPattern = process.argv[flagIndex + 1]
    const fileRegex = loadKnownErrorsFile()
    if (fileRegex === null) {
        return new RegExp(flagPattern)
    }
    return new RegExp(`${fileRegex.source}|${flagPattern}`)
}

// Read results.csv
export async function render() {
    const knownErrors = parseKnownErrors()
    const runs = load("results.csv")

    const regex = /(?<implA>.+) x (?<implB>.+) \((?<options>.*)\)/
    const parsedRuns = runs.map(run => {
        const match = run.name.match(regex)
        if (!match || match.groups === undefined) {
            throw new Error(`Run ID ${run.name} does not match the expected format`);
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

    const cellRender = makeDefaultCellRender(knownErrors)

    let outMd = ""

    for (const runGroup of Object.values(runsByOptions)) {
        outMd += `## Using: ${runGroup[0].options.join(", ")}\n`
        const table = generateTable(runGroup, ":white_circle:", cellRender)
        outMd += markdownTable(table)
        outMd += "\n\n"
    }

    // Collect all current failures (including known errors)
    const allFailures = parsedRuns.filter(r => r.outcome !== "success").map(r => r.name)

    // Known errors that now pass
    const knownErrorsPassing = parsedRuns
        .filter(r => r.outcome === "success" && knownErrors !== null && knownErrors.test(r.name))
        .map(r => r.name)

    if (knownErrorsPassing.length > 0) {
        outMd += `## Known errors now passing\n\n`
        outMd += `The following test cases were marked as known errors but are now passing. `
        outMd += `Consider removing them from the known errors list.\n\n`
        for (const name of knownErrorsPassing) {
            outMd += `- ${name}\n`
        }
        outMd += "\n"
    }

    if (allFailures.length > 0) {
        const escapedNames = allFailures.map(name => name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
        const regex = `^(${escapedNames.join("|")})$`
        outMd += `## Mark all errors as known\n\n`
        outMd += `To mark all current errors as known, pass the following flag:\n\n`
        outMd += "```\n"
        outMd += `--known-errors "${regex}"\n`
        outMd += "```\n"
    }

    console.log(outMd)

}

render()
