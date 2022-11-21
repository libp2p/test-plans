all: ./demo/results.csv ./demo/results.md

# combine versions into a list of combinations + the list of build targets
./demo/combinations.toml: ./index.ts ./demo/rust.toml ./demo/go.toml
	./node_modules/.bin/ts-node index.ts combine ./demo/combinations.toml ./demo/rust.toml ./demo/go.toml

# generate the list of every build-artifacts we need to run the tests
./demo/composition-interop-after-build.toml: ./demo/combinations.toml ./demo/composition-interop.toml
	make build-all

# extract the artifacts into a resource files
./demo/artifacts.toml: ./index.ts ./demo/composition-interop-after-build.toml
	./node_modules/.bin/ts-node index.ts extract-artifacts ./demo/artifacts.toml ./demo/composition-interop-after-build.toml

# call all the runs
./demo/results.csv: ./index.ts ./demo/composition-interop-after-build.toml ./demo/combinations.toml
	make run-all

./demo/results.md: ./index.ts ./demo/results.csv
	./node_modules/.bin/ts-node index.ts export-results ./demo/results.csv ./demo/results.md

# workaround poor write-artifacts feature
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
	cp /tmp/demo/composition-interop.toml ./demo/composition-interop-after-build.toml

run-all:
	RustLibp2pMasterSha=eb10af7 \
		GoLibp2pMasterSha="63b8803" \
		CustomRustGitTarget="" \
		CustomRustGitReference="" \
		CustomGoGitTarget="" \
		CustomGoGitReference="" \
		RunId=42 \
		testground run composition -f ./demo/composition-interop-after-build.toml --wait --result-file ./demo/results.csv