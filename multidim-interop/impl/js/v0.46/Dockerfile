# Here because we want to fetch the node_modules within docker so that it's
# installed on the same platform the test is run. Otherwise tools like `esbuild` will fail to run
FROM node:18.17.1
WORKDIR /app
RUN apt-get update && apt-get install -y cmake
COPY package*.json ./
RUN npm ci

WORKDIR /app/node_modules/@libp2p/multidim-interop

ENTRYPOINT [ "npm", "run", "test:interop:multidim", "--", "--build", "false", "--types", "false", "-t", "node" ]
