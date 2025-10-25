image_name := c-v0.0.1
commitSha := 23a617223a3bbfb4b2af8f219f389e440b9c1ac2
repo_url := https://github.com/Pier-Two/c-libp2p.git
dir_name := c-libp2p-$(commitSha)

all: image.json

image.json:
	rm -rf $(dir_name)
	git clone $(repo_url) $(dir_name)
	cd $(dir_name) && git checkout $(commitSha)
	cd $(dir_name) && git submodule update --init --recursive external/picoquic
	cd $(dir_name) && \
	mkdir -p external/secp256k1 && wget -O secp256k1.zip https://github.com/bitcoin-core/secp256k1/archive/master.zip && unzip -o secp256k1.zip && mv secp256k1-master/* external/secp256k1/ && rm -rf secp256k1.zip secp256k1-master && \
	mkdir -p external/libtomcrypt && wget -O libtomcrypt.zip https://github.com/libtom/libtomcrypt/archive/develop.zip && unzip -o libtomcrypt.zip && mv libtomcrypt-develop/* external/libtomcrypt/ && rm -rf libtomcrypt.zip libtomcrypt-develop && \
	mkdir -p external/libtommath && wget -O libtommath.zip https://github.com/libtom/libtommath/archive/master.zip && unzip -o libtommath.zip && mv libtommath-master/* external/libtommath/ && rm -rf libtommath.zip libtommath-master && \
	mkdir -p external/libeddsa && wget -O libeddsa.zip https://github.com/phlay/libeddsa/archive/master.zip && unzip -o libeddsa.zip && mv libeddsa-master/* external/libeddsa/ && rm -rf libeddsa.zip libeddsa-master && \
	mkdir -p external/noise-c && wget -O noise-c.zip https://github.com/uink45/noise-c/archive/master.zip && unzip -o noise-c.zip && mv noise-c-master/* external/noise-c/ && rm -rf noise-c.zip noise-c-master && \
	mkdir -p external/wjcryptlib && wget -O wjcryptlib.zip https://github.com/WaterJuice/WjCryptLib/archive/master.zip && unzip -o wjcryptlib.zip && mv WjCryptLib-master/* external/wjcryptlib/ && rm -rf wjcryptlib.zip WjCryptLib-master && \
	mkdir -p external/sha3 && wget -O sha3.zip https://github.com/pablotron/sha3/archive/main.zip && unzip -o sha3.zip && mv sha3-main/* external/sha3/ && rm -rf sha3.zip sha3-main && \
	mkdir -p external/c20p1305 && wget -O c20p1305.zip https://github.com/wg/c20p1305/archive/master.zip && unzip -o c20p1305.zip && mv c20p1305-master/* external/c20p1305/ && rm -rf c20p1305.zip c20p1305-master
	cd $(dir_name) && IMAGE_NAME=$(image_name) ../../../../dockerBuildWrapper.sh -f interop-tests/transport/Dockerfile .
	docker image inspect $(image_name) -f '{{.Id}}' | \
		xargs -I {} echo '{"imageID": "{}"}' > $@

clean:
	rm -rf image.json $(dir_name)

.PHONY: all clean
