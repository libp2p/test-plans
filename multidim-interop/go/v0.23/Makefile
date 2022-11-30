image.json: Dockerfile main.go go.mod go.sum
	echo "{\"imageID\": \"$(shell docker build . -q)\"}" > $@

clean:
	rm image.json