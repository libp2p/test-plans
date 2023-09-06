# Here because we want to fetch the node_modules within docker so that it's
# installed on the same platform the test is run. Otherwise tools like `esbuild` will fail to run
FROM node:18.17.1
WORKDIR /app
RUN npm install @libp2p/multidim-interop@1.0.0-c4eff4c5

WORKDIR /app/node_modules/@libp2p/multidim-interop

ENTRYPOINT [ "npm", "run", "test:interop:multidim", "--", "--build", "false", "--types", "false", "-t", "node" ]
