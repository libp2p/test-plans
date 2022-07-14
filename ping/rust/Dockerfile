FROM rust:1.62-bullseye as builder
WORKDIR /usr/src/testplan

RUN apt-get update && apt-get install -y cmake

# Cache dependencies between test runs, see testground examples.
RUN mkdir -p ./plan/src/
RUN echo "fn main() {}" > ./plan/src/main.rs
COPY ./plan/Cargo.lock ./plan/Cargo.toml ./plan/

ARG CARGO_FEATURES=""
ARG CARGO_PATCH=""
ARG CARGO_REMOVE=""

RUN echo "${CARGO_REMOVE}"
RUN if [ ! -z "${CARGO_REMOVE}" ]; then sed -i "s/^${CARGO_REMOVE}.*//" ./plan/Cargo.toml; fi
RUN echo "${CARGO_PATCH}" >> ./plan/Cargo.toml
RUN cat ./plan/Cargo.toml

RUN cd ./plan/ && \
        cargo update --dry-run
RUN cd ./plan/ && \
        cargo build --release --features="${CARGO_FEATURES}"

# Backup Cargo file to preserve patches.
RUN cp ./plan/Cargo.toml ./plan/Cargo.lock /tmp/

COPY . .

RUN mv /tmp/Cargo.toml /tmp/Cargo.lock ./plan

RUN cd ./plan/ && \
        cargo build --release --features="${CARGO_FEATURES}"

FROM debian:bullseye-slim
COPY --from=builder /usr/src/testplan/plan/target/release/testplan /usr/local/bin/testplan
EXPOSE 6060
ENTRYPOINT ["testplan"]