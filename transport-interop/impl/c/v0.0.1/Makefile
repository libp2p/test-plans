image_name := c-v0.0.1
commitSha := 2d6ccc96b39a5129ebdaf5b2577eba5880f3dc0a
repo_url := https://github.com/Pier-Two/c-libp2p.git
dir_name := c-libp2p-$(commitSha)

all: image.json

image.json:
	rm -rf $(dir_name)
	git clone $(repo_url) $(dir_name)
	cd $(dir_name) && git checkout $(commitSha)
	cd $(dir_name) && git submodule update --init --recursive lib/picoquic
	cd $(dir_name) && \
	mkdir -p lib/secp256k1 && wget -O secp256k1.zip https://github.com/bitcoin-core/secp256k1/archive/master.zip && unzip -o secp256k1.zip && mv secp256k1-master/* lib/secp256k1/ && rm -rf secp256k1.zip secp256k1-master && \
	mkdir -p lib/libtomcrypt && wget -O libtomcrypt.zip https://github.com/libtom/libtomcrypt/archive/develop.zip && unzip -o libtomcrypt.zip && mv libtomcrypt-develop/* lib/libtomcrypt/ && rm -rf libtomcrypt.zip libtomcrypt-develop && \
	mkdir -p lib/libtommath && wget -O libtommath.zip https://github.com/libtom/libtommath/archive/master.zip && unzip -o libtommath.zip && mv libtommath-master/* lib/libtommath/ && rm -rf libtommath.zip libtommath-master && \
	mkdir -p lib/libeddsa && wget -O libeddsa.zip https://github.com/phlay/libeddsa/archive/master.zip && unzip -o libeddsa.zip && mv libeddsa-master/* lib/libeddsa/ && rm -rf libeddsa.zip libeddsa-master && \
	mkdir -p lib/noise-c && wget -O noise-c.zip https://github.com/uink45/noise-c/archive/master.zip && unzip -o noise-c.zip && mv noise-c-master/* lib/noise-c/ && rm -rf noise-c.zip noise-c-master && \
	mkdir -p lib/wjcryptlib && wget -O wjcryptlib.zip https://github.com/WaterJuice/WjCryptLib/archive/master.zip && unzip -o wjcryptlib.zip && mv WjCryptLib-master/* lib/wjcryptlib/ && rm -rf wjcryptlib.zip WjCryptLib-master && \
	mkdir -p lib/sha3 && wget -O sha3.zip https://github.com/pablotron/sha3/archive/main.zip && unzip -o sha3.zip && mv sha3-main/* lib/sha3/ && rm -rf sha3.zip sha3-main && \
	mkdir -p lib/c20p1305 && wget -O c20p1305.zip https://github.com/wg/c20p1305/archive/master.zip && unzip -o c20p1305.zip && mv c20p1305-master/* lib/c20p1305/ && rm -rf c20p1305.zip c20p1305-master
	cd $(dir_name) && IMAGE_NAME=$(image_name) ../../../../dockerBuildWrapper.sh -f interop-tests/Dockerfile .
	docker image inspect $(image_name) -f '{{.Id}}' | \
		xargs -I {} echo '{"imageID": "{}"}' > $@

clean:
	rm -rf image.json $(dir_name)

.PHONY: all clean
