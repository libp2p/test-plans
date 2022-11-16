all: ./demo/results.csv ./demo/results.html

# combine versions into a list of combinations + the list of build targets
./demo/combinations.toml: ./index.ts ./demo/rust.toml ./demo/go.toml ./node_modules/.bin/ts-node
	./node_modules/.bin/ts-node index.ts combine ./demo/combinations.toml ./demo/rust.toml ./demo/go.toml

#We don't want to assume no one else is doing something similar elsewhere on the same machine, nor do we want to assume your TMPDIR is /tmp. Using != for portability between makes.
mktempd != mktemp -d
OURTMP ?= $(mktempd)

# generate the list of every build-artifacts we need to run the tests
$(OURTMP)/builds-artifacts.toml: ./demo/combinations.toml demo/composition-interop.toml
	make 'OURTMP=$(OURTMP)' build-all

# extract the artifacts into a resource files
./demo/artifacts.toml: ./index.ts $(OURTMP)/builds-artifacts.toml ./node_modules/.bin/ts-node
	./node_modules/.bin/ts-node index.ts extract-artifacts ./demo/artifacts.toml $(OURTMP)/builds-artifacts.toml

# call all the runs
./demo/results.csv: ./index.ts ./demo/composition-interop-runner.toml ./demo/artifacts.toml ./demo/combinations.toml
	make 'OURTMP=$(OURTMP)' run-all

./demo/results.html: ./index.ts ./demo/results.csv ./node_modules/.bin/ts-node
	./node_modules/.bin/ts-node index.ts export-results ./demo/results.csv ./demo/results.html

./node_modules/.bin/ts-node :
	npm install

build-all:
	rm -rf $(OURTMP)/demo/
	cp -R ./demo/ $(OURTMP)/demo/
	RustLibp2pMasterSha=eb10af7 \
		GoLibp2pMasterSha="63b8803" \
		CustomRustGitTarget="" \
		CustomRustGitReference="" \
		CustomGoGitTarget="" \
		CustomGoGitReference="" \
		RunId=42 \
		testground build composition -f $(OURTMP)/demo/composition-interop.toml --wait -w
	cp -v $(OURTMP)/demo/composition-interop.toml $(OURTMP)/builds-artifacts.toml
	echo "cat $(OURTMP)/builds-artifacts.toml to see the intermediate file"

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
