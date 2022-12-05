# Generate Dashboard

This script loads a Testground result file and generate a 2D matrix of the result.
It expect the result file to be the output of some pairwise testing, where each run-id is using the format `pair-1 x pair-2 ...rest`.

See `src/fixture.csv` for an example of input, and `src/fixture.md` for the expected output.

This is a simple dashboard destined to complete the interop testing, see [Issue 55](https://github.com/libp2p/test-plans/issues/55).

## Usage

`ts-node ./src/index.ts input_path.csv output_path.md`

If the ENV variable `RUN_URL` is set, each item in the URL will contains link to this URL.

## Dev

- `npm run lint` for linting
- `npm run test` to run the tests
- `npm run package` to generate the new dist file

## Output Example

|              | go-v0.20       | go-v0.21       | go-v0.22       | rust-v0.44.0   | rust-v0.45.1   | rust-v0.46.0   | rust-v0.47.0   |
| ------------ | -------------- | -------------- | -------------- | -------------- | -------------- | -------------- | -------------- |
| go-v0.20     | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.21     | :green_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| go-v0.22     | :green_circle: | :green_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.44.0 | :green_circle: | :green_circle: | :green_circle: | :white_circle: | :green_circle: | :green_circle: | :green_circle: |
| rust-v0.45.1 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :white_circle: | :red_circle:   | :red_circle:   |
| rust-v0.46.0 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle:   | :white_circle: | :red_circle:   |
| rust-v0.47.0 | :green_circle: | :green_circle: | :green_circle: | :green_circle: | :red_circle:   | :red_circle:   | :white_circle: |
