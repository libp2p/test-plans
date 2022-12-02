type PairOfImplementation = [string, string]

// `     something x something-lese    more info ignore`
const TASK_ID_MATCHER = /\s*(\S+)\s+x\s+(\S+)\s*.*/;

const fromTaskIdToCoordinate = (taskId: string): PairOfImplementation => {
  const match = taskId.match(TASK_ID_MATCHER);
  if (!match) {
    throw new Error(`Task ID ${taskId} does not match the expected format`);
  }

  return [match[1], match[2]];
};

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
    ["someid2 x anotherid2 (with additional parameters)", ["someid2", "anotherid2"]],
    ["someid x anotherid (with additional parameters)", ["someid", "anotherid"]],
  ])(
    "should parse pairs correctly: %s => %s",
    (taskId, pairs) => {
      expect(fromTaskIdToCoordinate(taskId)).toEqual(pairs);
    }
  );
});
