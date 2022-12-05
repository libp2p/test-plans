import fs from "fs";
import os from "os";
import path from "path";
import {
  CSVToMarkdown,
  fromRunIdToCoordinate,
  generateEmptyMatrix,
  generateTable,
  markdownTable,
  ResultFile
} from "./lib";

describe("conversion", () => {
  it.each(["random id", "almost xtherexfriend"])(
    "should throw on invalid run id: %s",
    (runId) => {
      expect(() => fromRunIdToCoordinate(runId)).toThrow();
    }
  );

  it.each([
    ["someid x anotherid", ["someid", "anotherid"]],
    ["go-v0.21 x go-v0.20", ["go-v0.21", "go-v0.20"]],
    [
      "someid2 x anotherid2 (with additional parameters)",
      ["someid2", "anotherid2"],
    ],
    [
      "someid x anotherid (with additional parameters)",
      ["someid", "anotherid"],
    ],
  ])("should parse pairs correctly: %s => %s", (runId, pairs) => {
    expect(fromRunIdToCoordinate(runId)).toEqual(pairs);
  });
});

describe("generate empty matrix", () => {
  it("should generate empty matrix", () => {
    const items = ["a", "b", "c"];

    const matrix = generateEmptyMatrix(items, "0");

    expect(matrix).toEqual([
      [" ", "a", "b", "c"],
      ["a", "0", "0", "0"],
      ["b", "0", "0", "0"],
      ["c", "0", "0", "0"],
    ]);
  });
});

describe("table generation", () => {
  const SIMPLE_RESULT_FILE: ResultFile = [
    {
      run_id: "go-v0.21 x go-v0.20",
      task_id: "some-id",
      outcome: "success",
      error: "",
    },
    {
      run_id: "go-v0.22 x go-v0.20",
      task_id: "some-id-2",
      outcome: "success",
      error: "",
    },
  ];

  it("generateTable for a simple file", () => {
    const table = generateTable(SIMPLE_RESULT_FILE);

    expect(table).toEqual([
      [" ", "go-v0.20", "go-v0.21", "go-v0.22"],
      ["go-v0.20", ":white_circle:", ":green_circle:", ":green_circle:"],
      ["go-v0.21", ":green_circle:", ":white_circle:", ":white_circle:"],
      ["go-v0.22", ":green_circle:", ":white_circle:", ":white_circle:"],
    ]);
  });
});

describe("markdown table rendering", () => {
  it("should generate markdown table", () => {
    const table = [
      [" ", "go-v0.20", "go-v0.21", "go-v0.22"],
      ["go-v0.20", ":white_circle:", ":green_circle:", ":green_circle:"],
      ["go-v0.21", ":green_circle:", ":white_circle:", ":white_circle:"],
      ["go-v0.22", ":green_circle:", ":white_circle:", ":white_circle:"],
    ];

    const markdown = markdownTable(table);

    expect(markdown).toEqual(`|   | go-v0.20 | go-v0.21 | go-v0.22 |
| - | -------- | -------- | -------- |
| go-v0.20 | :white_circle: | :green_circle: | :green_circle: |
| go-v0.21 | :green_circle: | :white_circle: | :white_circle: |
| go-v0.22 | :green_circle: | :white_circle: | :white_circle: |`);
  });
});

describe("full generation", () => {
  it("generate expected markdown", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "test-"));

    const inputFile = "./src/fixture.csv";
    const outputFile = path.join(tmpDir, "output.md");
    const expectedOutputFile = "./src/fixture.md";

    CSVToMarkdown(inputFile, outputFile);

    const output = fs.readFileSync(outputFile, "utf8");
    const expectedOutput = fs.readFileSync(expectedOutputFile, "utf8");

    expect(output).toEqual(expectedOutput);
  });
});
