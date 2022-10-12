all: ./results.txt

# combine versions into a list of combinations + the list of build targets
./partialized/combinations.toml: ./index.ts ./rust.toml ./go.toml
	./node_modules/.bin/ts-node index.ts combine

# generate the list of every build-artifacts we need to run the tests
./partialized/builds-artifacts.toml: ./index.ts ./partialized/composition-interop-builds.toml ./partialized/combinations.toml
	make build-all-demo

# extract the artifacts into a resource files
./partialized/artifacts.toml: ./index.ts ./partialized/builds-artifacts.toml
	./node_modules/.bin/ts-node index.ts gather-artifacts

# call all the runs
./results.txt: ./index.ts ./partialized/artifacts.toml ./partialized/composition-interop-run.toml
	make run-all-demo

build-all-demo:
	rm -rf ./tmp-partialized/
	cp -R ./partialized/ ./tmp-partialized/
	RustLibp2pMasterSha=eb10af7 \
		GoLibp2pMasterSha="63b8803" \
		CustomRustGitTarget="" \
		CustomRustGitReference="" \
		CustomGoGitTarget="" \
		CustomGoGitReference="" \
		RunId=42 \
		testground build composition -f ./tmp-partialized/composition-interop-builds.toml --wait -w
	cp ./tmp-partialized/composition-interop-builds.toml ./partialized/builds-artifacts.toml

run-all-demo:
	mkdir -p ./runs/
	RustLibp2pMasterSha=eb10af7 \
		GoLibp2pMasterSha="63b8803" \
		CustomRustGitTarget="" \
		CustomRustGitReference="" \
		CustomGoGitTarget="" \
		CustomGoGitReference="" \
		RunId=42 \
		./node_modules/.bin/ts-node index.ts foreach run composition -f ./partialized/composition-interop-run.toml --wait --collect --collect-file runs/__TEST_RUN_ID__.tgz