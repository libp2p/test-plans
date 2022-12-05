import * as csv from "csv-parse/sync";
import fs from "fs";

type ResultLine = {
  task_id: string;
  run_id: string;
  outcome: string;
  error: string;
};

export type ResultFile = ResultLine[];

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

export const generateTable = (results: ResultFile): string[][] => {
  const pairs = results.map((x) => fromRunIdToCoordinate(x.run_id));
  const uniqPairs = listUniqPairs(pairs);

  const matrix = generateEmptyMatrix(uniqPairs, ":white_circle:");

  for (const result of results) {
    const [a, b] = fromRunIdToCoordinate(result.run_id);
    const i = uniqPairs.indexOf(a);
    const j = uniqPairs.indexOf(b);

    if (result.outcome === "success") {
      matrix[i + 1][j + 1] = ":green_circle:";
      matrix[j + 1][i + 1] = ":green_circle:";
    } else {
      matrix[i + 1][j + 1] = ":red_circle:";
      matrix[j + 1][i + 1] = ":red_circle:";
    }
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
