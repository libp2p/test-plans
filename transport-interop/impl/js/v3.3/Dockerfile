# install node and browsers
FROM mcr.microsoft.com/playwright:v1.50.1

WORKDIR /app

COPY package*.json .aegir.js tsconfig.json ./
COPY src ./src
COPY test ./test

# disable colored output and CLI animation from test runners
ENV CI=true

# install inside the container so any native deps will have the docker arch
RUN npm ci
RUN npm run build

ENTRYPOINT npm test -- -t node -- --exit
