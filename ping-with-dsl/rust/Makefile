image.0.49.0.json: Dockerfile src/*/*.rs Cargo.lock Cargo.toml
	echo "{\"imageID\": \"$(shell docker build . -q  --build-arg BINARY_NAME=testplan_0490)\"}" > $@

clean:
	rm image.0.49.0.json

# [[groups]]
# Id = '0.48.0'
# BinaryName = 'testplan_0480'

# [[groups]]
# Id = "v0.47.0"
# BinaryName = 'testplan_0470'

# [[groups]]
# Id = "v0.46.1"
# BinaryName = 'testplan_0461'

# [[groups]]
# Id = "v0.45.1"
# BinaryName = 'testplan_0451'

# [[groups]]
# Id = "v0.44.0"
# BinaryName = 'testplan_0440'
