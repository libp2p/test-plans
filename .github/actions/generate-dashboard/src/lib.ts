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
