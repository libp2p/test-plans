# syntax=docker/dockerfile:1

FROM node:17

WORKDIR /app

COPY package*.json .

RUN npm ci

COPY *.js /app/

EXPOSE 6060
ENTRYPOINT [ "npm", "run", "start" ]