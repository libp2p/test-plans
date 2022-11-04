FROM rust:1.62-bullseye as builder
WORKDIR /usr/src/testplan

RUN apt-get update && apt-get install -y cmake protobuf-compiler

ARG PLAN_PATH="./"

# Cache dependencies between test runs, see testground examples.
RUN mkdir -p ./plan/src/
RUN echo "fn main() { println!(\"If you see this message, you may want to clean up the target directory or the Docker build cache.\") }" > ./plan/src/main.rs
COPY ./plan/${PLAN_PATH}/Cargo.lock ./plan/${PLAN_PATH}/Cargo.toml ./plan/

RUN cd ./plan/ && \
        cargo fetch && \
        # use a default feature to rely on docker caching.
        cargo build --release

ARG GIT_TARGET=""
ARG UPDATE_CMD=""

RUN if [ ! -z "${GIT_TARGET}" ]; then sed -i "s/https:\/\/github.com\/libp2p\/rust-libp2p/${GIT_TARGET}/" ./plan/Cargo.toml; fi
RUN if [ ! -z "${UPDATE_CMD}" ]; then ${UPDATE_CMD}; fi

# Backup Cargo file to preserve patches.
RUN cp ./plan/Cargo.toml ./plan/Cargo.lock /tmp/

COPY ./plan/${PLAN_PATH} ./plan

# This is in order to make sure `main.rs`s mtime timestamp is updated to avoid the dummy `main`
# remaining in the release binary.
# https://github.com/rust-lang/cargo/issues/9598
RUN touch ./plan/src/main.rs

RUN mv /tmp/Cargo.toml /tmp/Cargo.lock ./plan

ARG BINARY_NAME

RUN cd ./plan/ && \
        cargo build --release --bin="${BINARY_NAME}"

FROM debian:bullseye-slim
COPY --from=builder /usr/src/testplan/plan/target/release/"${BINARY_NAME}" /usr/local/bin/testplan
EXPOSE 6060
ENV RUST_BACKTRACE=1
ENTRYPOINT ["testplan"]
