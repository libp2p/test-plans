FROM node:18

WORKDIR /app
COPY . .
RUN npm i && npm run build
COPY ./packages/perf/package.json ./packages/perf/package.json
RUN cd packages/perf && npm i && npm run build

WORKDIR /app/packages/perf

ENTRYPOINT [  "/src/dist/main.js" ]