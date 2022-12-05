import * as core from '@actions/core';
import process from "process";
import { CSVToMarkdown } from "./lib";

const main = async () => {
  const csvInputPath = core.getInput('input_csv')
  const markdownOutputPath = core.getInput('output_markdown')

  core.debug(`Genrating dasbhoard from ${csvInputPath} to ${markdownOutputPath}`)

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
