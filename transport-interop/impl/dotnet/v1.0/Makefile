image_name := dotnet-v1.0
commitSha := v1.0.0-interop.1

all: image.json

image.json:
    cd dotnet-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f src/samples/transport-interop/Dockerfile .
    docker image inspect ${image_name} -f "{{.Id}}" | \
        xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

dotnet-libp2p-${commitSha}: dotnet-libp2p-${commitSha}.zip
    unzip -o dotnet-libp2p-${commitSha}.zip

dotnet-libp2p-${commitSha}.zip:
    wget -O $@ "https://github.com/NethermindEth/dotnet-libp2p/archive/v1.0.0-interop.1.zip"

clean:
    rm image.json
    rm dotnet-libp2p-*.zip
    rm -rf dotnet-libp2p-*
