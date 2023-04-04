# syntax=docker/dockerfile:1
FROM node:18

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY tsconfig.json .
COPY .aegir.js .
COPY test ./test
COPY src ./src

RUN npm run build

ENTRYPOINT [ "npm", "test", "--", "--build", "false", "--types", "false", "-t", "node" ]
