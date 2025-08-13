image_name := dotnet-v1.0
commitSha := 91be8757237dba57b1f1688799c4fec808060fdb

all: image.json

image.json: dotnet-libp2p-${commitSha}
	cd dotnet-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f src/samples/transport-interop/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

dotnet-libp2p-${commitSha}: dotnet-libp2p-${commitSha}.zip
	unzip -o dotnet-libp2p-${commitSha}.zip

dotnet-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/NethermindEth/dotnet-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm dotnet-libp2p-*.zip
	rm -rf dotnet-libp2p-*
