# syntax=docker/dockerfile:1

FROM node:22-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-alpine
WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apk apk add bind-tools jq curl tcpdump iproute2

COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --omit=dev
COPY --from=builder /app/dist ./dist

RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' > /usr/bin/hole-punch-client \
    && chmod +x /usr/bin/hole-punch-client
