# Here because we want to fetch the node_modules within docker so that it's
# installed on the same platform the test is run. Otherwise tools like `esbuild` will fail to run
FROM node:20.13.1
WORKDIR /app
RUN apt-get update && apt-get install -y cmake
COPY package*.json ./
RUN npm ci

WORKDIR /app/node_modules/@libp2p/multidim-interop
# Patch the test to use IPv4 loopback address explicitly. Sometimes localhost resolves to the IPv6 address
RUN sed -i 's/localhost/127.0.0.1/g' .aegir.js test/ping.spec.ts dist/test/ping.spec.js

ENTRYPOINT [ "npm", "run", "test:interop:multidim", "--", "--build", "false", "--types", "false", "-t", "node" ]
