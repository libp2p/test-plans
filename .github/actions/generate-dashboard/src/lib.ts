import * as csv from "csv-parse/sync";
import fs from "fs";

export type ResultLine = {
  task_id: string;
  run_id: string;
  outcome: string;
  error: string;
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

// `     something x something-else    more info ignore`
const RUN_ID_MATCHER = /\s*(\S+)\s+x\s+(\S+)\s*.*/;

export const fromRunIdToCoordinate = (runId: string): PairOfImplementation => {
  const match = runId.match(RUN_ID_MATCHER);
  if (!match) {
    throw new Error(`Task ID ${runId} does not match the expected format`);
  }

  return [match[1], match[2]];
};

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
  results: ResultFile,
  defaultValue: string = ":white_circle:",
  testedCell: CellRender = defaultCellRender
): string[][] => {
  const pairs = results.map((x) => fromRunIdToCoordinate(x.run_id));
  const uniqPairs = listUniqPairs(pairs);

  const matrix = generateEmptyMatrix(uniqPairs, defaultValue);

  for (const result of results) {
    const [a, b] = fromRunIdToCoordinate(result.run_id);
    const i = uniqPairs.indexOf(a);
    const j = uniqPairs.indexOf(b);

    const cell = testedCell(a, b, result);

    matrix[i + 1][j + 1] = cell;
    matrix[j + 1][i + 1] = cell;
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

export const CSVToMarkdown = (csvInputPath: string, outputMarkdown: string) => {
  const results = load(csvInputPath);
  const table = generateTable(results);
  const content = markdownTable(table);

  save(outputMarkdown, content);
};
