# syntax=docker/dockerfile:1
# Using playwright so that we have the same base across NodeJS + Browser tests
FROM mcr.microsoft.com/playwright

WORKDIR /app

COPY package*.json .

RUN npm ci

# Install browsers, Needed for the browser tests, but we do it here so we have the same base
RUN ./node_modules/.bin/playwright install

COPY tsconfig.json .
COPY .aegir.js .
COPY test ./test
COPY src ./src

RUN npm run build

ENTRYPOINT [ "npm", "test", "--", "--build", "false", "--types", "false", "-t", "node" ]
