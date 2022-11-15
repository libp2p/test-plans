FROM rust:1.62-bullseye as builder
WORKDIR /usr/src/testplan

RUN apt-get update && apt-get install -y cmake protobuf-compiler

ARG PLAN_PATH="./"

# COPY ./plan/${PLAN_PATH} ./plan
COPY ./ ./plan

RUN cd ./plan/ && cargo build

ARG GIT_TARGET=""
RUN if [ ! -z "${GIT_TARGET}" ]; then sed -i "s/https:\/\/github.com\/libp2p\/rust-libp2p/${GIT_TARGET}/" ./plan/Cargo.toml; fi

ARG GIT_REF=""
RUN if [ ! -z "${GIT_REF}" ]; then sed -i "s/368705a1465c4322948d14ee46d42475c472ca1e/${GIT_REF}/" ./plan/Cargo.toml; fi

ARG BINARY_NAME

RUN cd ./plan/ && cargo build --bin="${BINARY_NAME}"

FROM debian:bullseye-slim
COPY --from=builder /usr/src/testplan/plan/target/debug/"${BINARY_NAME}" /usr/local/bin/testplan
EXPOSE 6060
ENV RUST_BACKTRACE=1
ENTRYPOINT ["testplan"]
