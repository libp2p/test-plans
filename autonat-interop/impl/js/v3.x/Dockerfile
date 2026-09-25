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

COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --omit=dev
COPY --from=builder /app/dist ./dist

RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' > /usr/bin/autonat-client \
    && chmod +x /usr/bin/autonat-client
CMD ["autonat-client"]
