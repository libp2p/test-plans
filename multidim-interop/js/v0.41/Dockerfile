# syntax=docker/dockerfile:1

FROM node:17

WORKDIR /app

COPY package*.json .

RUN npm ci

COPY *.js /app/

ENTRYPOINT [ "npm", "run", "start" ]