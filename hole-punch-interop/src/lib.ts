import * as csv from "csv-parse/sync";
import fs from "fs";

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
export const defaultCellRender: CellRender = (a, b, line) => {
  let result = ":red_circle:";

  if (line.outcome === "success") {
    result = ":green_circle:";
  }

  if (process.env.RUN_URL) {
    result = `[${result}](${process.env.RUN_URL})`;
  }

  return result;
};

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
  matrix[0][0] = "⬇️ dialer 📞 \\  ➡️ listener 🎧"

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
