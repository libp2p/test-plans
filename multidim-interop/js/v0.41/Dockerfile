# syntax=docker/dockerfile:1

FROM node:16

WORKDIR /app

COPY package*.json ./app/

RUN npm ci

COPY *.js /app/

EXPOSE 6060
ENTRYPOINT [ "npm", "run", "start" ]