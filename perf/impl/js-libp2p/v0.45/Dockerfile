# Here because we want to fetch the node_modules within docker so that it's
# installed on the same platform the test is run. Otherwise tools like `esbuild` will fail to run
FROM node:18
WORKDIR /app
COPY . .
RUN npm i && npm run build

WORKDIR /app/packages/perf
RUN npm i && npm run build

ENTRYPOINT [ "npm", "run", "start" ]