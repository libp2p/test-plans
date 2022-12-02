interface ICoordinates {
  x: number;
  y: number;
}

const fromTaskIdToCoordinate = (taskId: string): ICoordinates => {
  throw new Error("Not implemented");
};

describe("convesion", () => {
  it.each(["random id", "almost x there x friend"])(
    "should throw on invalid taskId: %s",
    (taskId) => {
      expect(() => fromTaskIdToCoordinate(taskId)).toThrow();
    }
  );
});
