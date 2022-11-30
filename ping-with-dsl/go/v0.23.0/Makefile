image.json: Dockerfile main.go go.mod
	echo "{\"imageID\": \"$(shell docker build . -q)\"}" > $@

clean:
	rm image.json