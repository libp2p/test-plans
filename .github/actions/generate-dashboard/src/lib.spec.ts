import {
  fromTaskIdToCoordinate,
  generateEmptyMatrix,
  generateTable,
  markdownTable,
  ResultFile
} from "./lib";

describe("conversion", () => {
  it.each(["random id", "almost xtherexfriend"])(
    "should throw on invalid taskId: %s",
    (taskId) => {
      expect(() => fromTaskIdToCoordinate(taskId)).toThrow();
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
  ])("should parse pairs correctly: %s => %s", (taskId, pairs) => {
    expect(fromTaskIdToCoordinate(taskId)).toEqual(pairs);
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
      task_id: "go-v0.21 x go-v0.20",
      run_id: "run-id-1",
      outcome: "success",
      error: "",
    },
    {
      task_id: "go-v0.22 x go-v0.20",
      run_id: "run-id-1",
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
