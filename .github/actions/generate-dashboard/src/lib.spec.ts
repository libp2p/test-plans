import { fromTaskIdToCoordinate } from "./lib";

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
