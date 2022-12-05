import fs from "fs";
import os from "os";
import path from "path";
import {
  CSVToMarkdown,
  defaultCellRender,
  fromRunIdToCoordinate,
  generateEmptyMatrix,
  generateTable,
  markdownTable,
  ResultFile,
  ResultLine
} from "./lib";

describe("default cell renderer", () => {
  it("render a green circle in in the simple case", () => {
    const result: ResultLine = {
      run_id: "go-v0.21 x go-v0.20",
      task_id: "some-id",
      outcome: "success",
      error: "",
    };

    const [a, b] = fromRunIdToCoordinate(result.run_id);
    expect(defaultCellRender(a, b, result)).toEqual(":green_circle:");
  });

  it("render a red circle in error cases", () => {
    const result: ResultLine = {
      run_id: "go-v0.21 x go-v0.20",
      task_id: "some-id",
      outcome: "failure",
      error: "",
    };

    const [a, b] = fromRunIdToCoordinate(result.run_id);
    expect(defaultCellRender(a, b, result)).toEqual(":red_circle:");
  });

  it("render a green circle with URL when there is an env variable", () => {
    const result: ResultLine = {
      run_id: "go-v0.21 x go-v0.20",
      task_id: "some-id",
      outcome: "success",
      error: "",
    };

    process.env.RUN_URL = "https://some-url.com";

    const [a, b] = fromRunIdToCoordinate(result.run_id);
    expect(defaultCellRender(a, b, result)).toEqual(
      "[:green_circle:](https://some-url.com)"
    );

    delete process.env.RUN_URL;
  });
});

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

  it("generateTable accept a function applied to each cell", () => {
    const table = generateTable(
      SIMPLE_RESULT_FILE,
      "was_not_tested",
      (x) => "was_tested"
    );

    expect(table).toEqual([
      [" ", "go-v0.20", "go-v0.21", "go-v0.22"],
      ["go-v0.20", "was_not_tested", "was_tested", "was_tested"],
      ["go-v0.21", "was_tested", "was_not_tested", "was_not_tested"],
      ["go-v0.22", "was_tested", "was_not_tested", "was_not_tested"],
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
