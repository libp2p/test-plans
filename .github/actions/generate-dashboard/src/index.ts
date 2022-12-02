import process from "process";

const main = async () => {
  throw new Error("Not implemented");
};

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
