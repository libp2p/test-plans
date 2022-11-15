FROM rust:1.62-bullseye as builder
WORKDIR /usr/src/testplan

RUN apt-get update && apt-get install -y cmake protobuf-compiler

ARG PLAN_PATH="./"
COPY ./plan/${PLAN_PATH} ./plan
RUN cd ./plan/ && cargo build  # Initial build acts as a cache.

ARG GIT_TARGET=""
RUN if [ ! -z "${GIT_TARGET}" ]; then sed -i "s,^git.*,git = \"https://${GIT_TARGET}\"," ./plan/Cargo.toml; fi

ARG GIT_REF=""
RUN if [ ! -z "${GIT_REF}" ]; then sed -i "s/^rev.*/rev = \"${GIT_REF}\"/" ./plan/Cargo.toml; fi

ARG BINARY_NAME
RUN cd ./plan/ && cargo build --bin="${BINARY_NAME}" # Cargo will update lockfile on changed manifest (i.e. if one of the above `sed`s patched it)

FROM debian:bullseye-slim
COPY --from=builder "/usr/src/testplan/plan/target/debug/${BINARY_NAME}" /usr/local/bin/testplan
EXPOSE 6060
ENV RUST_BACKTRACE=1
ENTRYPOINT ["/usr/local/bin/testplan"]
