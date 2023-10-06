image_name := dotnet-v1.0

all: image.json

image.json: Dockerfile Program.cs packages.lock.json TestPlansApp.csproj TestPlansApp.sln
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: clean all

clean:
	rm -f bin/ obj/
