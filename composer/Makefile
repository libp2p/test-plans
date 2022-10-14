all: ./demo/results.csv ./demo/results.md

# combine versions into a list of combinations + the list of build targets
./demo/combinations.toml: ./index.ts ./demo/rust.toml ./demo/go.toml
	./node_modules/.bin/ts-node index.ts combine ./demo/combinations.toml ./demo/rust.toml ./demo/go.toml

# generate the list of every build-artifacts we need to run the tests
/tmp/builds-artifacts.toml: ./demo/combinations.toml ./demo/composition-interop.toml
	make build-all

# extract the artifacts into a resource files
./demo/artifacts.toml: ./index.ts /tmp/builds-artifacts.toml
	./node_modules/.bin/ts-node index.ts extract-artifacts ./demo/artifacts.toml /tmp/builds-artifacts.toml

# call all the runs
./demo/results.csv: ./index.ts ./demo/composition-interop-runner.toml ./demo/artifacts.toml ./demo/combinations.toml
	make run-all

./demo/results.md: ./index.ts ./demo/results.csv
	./node_modules/.bin/ts-node index.ts export-results ./demo/results.csv ./demo/results.md

build-all:
	rm -rf /tmp/demo/
	cp -R ./demo/ /tmp/demo/
	RustLibp2pMasterSha=eb10af7 \
		GoLibp2pMasterSha="63b8803" \
		CustomRustGitTarget="" \
		CustomRustGitReference="" \
		CustomGoGitTarget="" \
		CustomGoGitReference="" \
		RunId=42 \
		testground build composition -f /tmp/demo/composition-interop.toml --wait -w
	cp /tmp/demo/composition-interop.toml /tmp/builds-artifacts.toml
	echo "cat /tmp/builds-artifacts.toml to see the intermediate file"

run-all:
	rm -rf ./runs/
	mkdir -p ./runs/
	RustLibp2pMasterSha=eb10af7 \
		GoLibp2pMasterSha="63b8803" \
		CustomRustGitTarget="" \
		CustomRustGitReference="" \
		CustomGoGitTarget="" \
		CustomGoGitReference="" \
		RunId=42 \
		./node_modules/.bin/ts-node index.ts foreach ./demo/results.csv run composition -f ./demo/composition-interop-runner.toml --wait --collect --collect-file runs/__TEST_RUN_ID__.tgz