import process from "process";
import { load, generateTable, markdownTable, save, CSVToMarkdown } from "./lib";

const main = async () => {
  const args: string[] = process.argv.slice(2);
  const [csvInputPath, markdownOutputPath] = args;
  CSVToMarkdown(csvInputPath, markdownOutputPath);
};

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
