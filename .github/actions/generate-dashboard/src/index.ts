import process from "process";
import { load, generateTable, markdownTable, save } from "./lib";

const main = async () => {
  const args: string[] = process.argv.slice(2);
  const [csvInputPath, markdownOutputPath] = args;

  const results = load(csvInputPath);
  const table = generateTable(results);
  const content = markdownTable(table);

  save(markdownOutputPath, content);
};

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
