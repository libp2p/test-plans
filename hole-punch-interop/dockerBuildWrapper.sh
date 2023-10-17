#!/usr/bin/env /bin/bash

# Detect the host architecture
HOST_ARCH=$(uname -m)

# Translate to Rust target
if [[ "$HOST_ARCH" == "x86_64" ]]; then
    RUST_TARGET="x86_64-unknown-linux-musl"
elif [[ "$HOST_ARCH" == "arm64" ]]; then
    RUST_TARGET="aarch64-unknown-linux-gnu"
else
    echo "Unsupported architecture: $HOST_ARCH"
    exit 1
fi

CACHING_OPTIONS=""
# If in CI and we have a defined cache bucket, use caching
if [[ -n "${CI}" ]] && [[ -n "${AWS_BUCKET}" ]]; then
    CACHING_OPTIONS="\
        --cache-to   type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME \
        --cache-from type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME"
fi

docker buildx build \
    --load \
    --build-arg TARGET_ARCH=$RUST_TARGET \
    -t $IMAGE_NAME $CACHING_OPTIONS "$@"
