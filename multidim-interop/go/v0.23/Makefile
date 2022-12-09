image.json: Dockerfile main.go go.mod go.sum
	echo "{\"imageID\": \"$(shell docker build . -q)\"}" > $@

.PHONY: clean

clean:
	rm image.json