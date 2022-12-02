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
const TASK_ID_MATCHER = /\s*(\S+)\s+x\s+(\S+)\s*.*/;

export const fromTaskIdToCoordinate = (
  taskId: string
): PairOfImplementation => {
  const match = taskId.match(TASK_ID_MATCHER);
  if (!match) {
    throw new Error(`Task ID ${taskId} does not match the expected format`);
  }

  return [match[1], match[2]];
};
