import { generateTable, load, makeDefaultCellRender, markdownTable, parseKnownErrors } from './src/lib'

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

    // Collect all current failures (including known errors)
    const allFailures = parsedRuns.filter(r => r.outcome !== "success").map(r => r.name)

    if (allFailures.length > 0) {
        const escapedNames = allFailures.map(name => name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
        const allRegex = `^(${escapedNames.join("|")})$`
        outMd += `## Mark all errors as known\n\n`
        outMd += `To mark all current errors as known, pass the following flag:\n\n`
        outMd += "```\n"
        outMd += `--known-errors "${allRegex}"\n`
        outMd += "```\n"
    }

    console.log(outMd)
}

render()
