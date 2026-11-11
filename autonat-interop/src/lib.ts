import * as csv from "csv-parse/sync";
import fs from "fs";
import path from "path";

// loadKnownErrorsFile reads the knownErrors.json regex list into a single
// RegExp, or null when the file is absent, empty or explicitly ignored.
export function loadKnownErrorsFile(): RegExp | null {
  if (process.argv.includes("--ignore-known-errors-file")) {
    return null;
  }
  const knownErrorsPath = path.join(__dirname, "..", "knownErrors.json");
  if (!fs.existsSync(knownErrorsPath)) {
    return null;
  }
  const patterns: string[] = JSON.parse(fs.readFileSync(knownErrorsPath, "utf8"));
  if (patterns.length === 0) {
    return null;
  }
  return new RegExp(patterns.join("|"));
}

// parseKnownErrors merges the knownErrors.json file with any --known-errors
// flag passed on the command line.
export function parseKnownErrors(): RegExp | null {
  const flagIndex = process.argv.indexOf("--known-errors");
  if (flagIndex === -1 || flagIndex + 1 >= process.argv.length) {
    return loadKnownErrorsFile();
  }
  const flagPattern = process.argv[flagIndex + 1];
  const fileRegex = loadKnownErrorsFile();
  if (fileRegex === null) {
    return new RegExp(flagPattern);
  }
  return new RegExp(`${fileRegex.source}|${flagPattern}`);
}

export type ResultLine = {
  name: string;
  outcome: string;
  error: string;
};

export type ParsedResultLine = {
  name: string;
  outcome: string;
  error: string;
  implA: string;
  implB: string;
};

export type ResultFile = ResultLine[];

export type CellRender = (a: string, b: string, line: ResultLine) => string;

/**
 * called for every cell in the table.
 *
 * This is designed to let future implementers add more complex ouput interpretation, with nested tables, etc.
 */
export const makeDefaultCellRender = (knownErrors: RegExp | null = null): CellRender => (a, b, line) => {
  let result = ":red_circle:";

  if (line.outcome === "success") {
    result = ":green_circle:";
  } else if (knownErrors !== null && knownErrors.test(line.name)) {
    result = ":yellow_circle:";
  }

  if (process.env.RUN_URL) {
    result = `[${result}](${process.env.RUN_URL})`;
  }

  return result;
};

export const defaultCellRender: CellRender = makeDefaultCellRender();

export const load = (path: string): ResultFile => {
  return csv.parse(fs.readFileSync(path, "utf8"), {
    columns: true,
    skip_empty_lines: true,
    delimiter: ",",
  }) as ResultFile;
};

export const save = (path: string, content: string) => {
  fs.writeFileSync(path, content);
};

type PairOfImplementation = [string, string];

export const listUniqPairs = (pairs: PairOfImplementation[]): string[] => {
  const uniq = new Set<string>();

  for (const [a, b] of pairs) {
    uniq.add(a);
    uniq.add(b);
  }

  return Array.from(uniq).sort();
};

export const generateEmptyMatrix = (
  keys: string[],
  defaultValue: string
): string[][] => {
  const header = [" ", ...keys];

  const matrix = [header];
  const rowOfDefaultValues = Array<string>(keys.length).fill(defaultValue);

  for (const key of keys) {
    const row = [key, ...rowOfDefaultValues];
    matrix.push(row);
  }

  return matrix;
};

export const generateTable = (
  results: Array<ParsedResultLine>,
  defaultValue: string = ":white_circle:",
  testedCell: CellRender = defaultCellRender
): string[][] => {
  const pairs = results.map(({ implA, implB }) => [implA, implB] as PairOfImplementation);
  const uniqPairs = listUniqPairs(pairs);

  const matrix = generateEmptyMatrix(uniqPairs, defaultValue);
  matrix[0][0] = "⬇️ client 📞 \\  ➡️ server 🎧"

  for (const result of results) {
    const { implA, implB } = result
    const i = uniqPairs.indexOf(implA);
    const j = uniqPairs.indexOf(implB);

    const cell = testedCell(implA, implB, result);

    matrix[i + 1][j + 1] = cell;
  }

  return matrix;
};

export const markdownTable = (table: string[][]): string => {
  const wrapped = (x: string) => `| ${x} |`;

  const header = table[0].join(" | ");
  const separator = table[0].map((x) => "-".repeat(x.length)).join(" | ");

  const rows = table.slice(1).map((row) => row.join(" | "));

  const body = [wrapped(header), wrapped(separator), ...rows.map(wrapped)].join(
    "\n"
  );

  return body;
};

export function sanitizeComposeName(name: string) {
  return name.replace(/[^a-zA-Z0-9_-]/g, "_");
}
