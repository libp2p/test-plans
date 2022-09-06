FROM rust:1.62-slim-bullseye as builder
WORKDIR /usr/src/testplan

RUN apt-get update && \
        apt-get install -y cmake protobuf-compiler && \
        rm -rf /var/lib/apt/lists/*

ARG PLAN_PATH="./"

# Cache dependencies between test runs, see testground examples.
RUN mkdir -p ./plan/src/
RUN echo "fn main() { println!(\"If you see this message, you may want to clean up the target directory or the Docker build cache.\") }" > ./plan/src/main.rs
COPY ./plan/${PLAN_PATH}/Cargo.lock ./plan/${PLAN_PATH}/Cargo.toml ./plan/

RUN cd ./plan/ && \
        cargo update --dry-run && \
        cargo fetch && \
        # use a default feature to rely on docker caching.
        cargo build --release --features "libp2pv0450"

# this arg will trigger a re-run and bump the master cache when needed
ARG RUST_LIBP2P_MASTER_SHA=""
RUN cd ./plan/ && \
        cargo update --dry-run && \
        cargo fetch && \
        # use a default feature to rely on docker caching.
        cargo build --release --features "libp2pv0450"

ARG CARGO_PATCH=""
ARG CARGO_REMOVE=""

RUN if [ ! -z "${CARGO_REMOVE}" ]; then sed -i "s/^${CARGO_REMOVE}.*//" ./plan/Cargo.toml; fi
RUN echo "${CARGO_PATCH}" >> ./plan/Cargo.toml

# Backup Cargo file to preserve patches.
RUN cp ./plan/Cargo.toml ./plan/Cargo.lock /tmp/

COPY ./plan/${PLAN_PATH} ./plan

# This is in order to make sure `main.rs`s mtime timestamp is updated to avoid the dummy `main`
# remaining in the release binary.
# https://github.com/rust-lang/cargo/issues/9598
RUN touch ./plan/src/main.rs

RUN mv /tmp/Cargo.toml /tmp/Cargo.lock ./plan

ARG CARGO_FEATURES=""

RUN cd ./plan/ && \
        cargo build --release --features="${CARGO_FEATURES}"

LABEL testground.image.type="test"
LABEL testground.test.lifecycle="build"
LABEL testground.test.lang="rust"
LABEL testground.test.test="ping"
ARG RUN_ID="-"
LABEL testground.run_id="${RUN_ID}"


FROM debian:bullseye-slim
COPY --from=builder /usr/src/testplan/plan/target/release/testplan /usr/local/bin/testplan
EXPOSE 6060
ENV RUST_BACKTRACE=1
ENTRYPOINT ["testplan"]

LABEL testground.image.type="test"
LABEL testground.test.lifecycle="run"
LABEL testground.test.lang="rust"
LABEL testground.test.test="ping"
ARG RUN_ID="-"
LABEL testground.run_id="${RUN_ID}"
