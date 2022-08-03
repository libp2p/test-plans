FROM rust:1.62-bullseye as builder
WORKDIR /usr/src/testplan

RUN apt-get update && apt-get install -y cmake

ARG PLAN_PATH="./"

# Cache dependencies between test runs, see testground examples.
RUN mkdir -p ./plan/src/
RUN echo "fn main() { println!(\"If you see this message, you may want to clean up the target directory or the Docker build cache.\") }" > ./plan/src/main.rs
COPY ./plan/${PLAN_PATH}/Cargo.lock ./plan/${PLAN_PATH}/Cargo.toml ./plan/

ARG CARGO_PATCH=""
ARG CARGO_REMOVE=""

RUN if [ ! -z "${CARGO_REMOVE}" ]; then sed -i "s/^${CARGO_REMOVE}.*//" ./plan/Cargo.toml; fi
RUN echo "${CARGO_PATCH}" >> ./plan/Cargo.toml
RUN cat ./plan/Cargo.toml

ARG CARGO_FEATURES=""

RUN cd ./plan/ && \
        cargo update --dry-run && \
        cargo build --release --features="${CARGO_FEATURES}"

# Backup Cargo file to preserve patches.
RUN cp ./plan/Cargo.toml ./plan/Cargo.lock /tmp/

COPY ./plan/${PLAN_PATH} ./plan

# This is in order to make sure `main.rs`s mtime timestamp is updated to avoid the dummy `main`
# remaining in the release binary.
# https://github.com/rust-lang/cargo/issues/9598
RUN touch ./plan/src/main.rs

RUN mv /tmp/Cargo.toml /tmp/Cargo.lock ./plan

RUN cd ./plan/ && \
        cargo build --release --features="${CARGO_FEATURES}"

FROM debian:bullseye-slim
COPY --from=builder /usr/src/testplan/plan/target/release/testplan /usr/local/bin/testplan
EXPOSE 6060
ENV RUST_BACKTRACE=1
ENTRYPOINT ["testplan"]