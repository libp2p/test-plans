#!/usr/bin/env /bin/bash

CACHING_OPTIONS=""
# If in CI and we have a defined cache bucket, use caching
if [[ -n "${CI}" ]] && [[ -n "${AWS_BUCKET}" ]]; then
    CACHING_OPTIONS="\
        --cache-to   type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME \
        --cache-from type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME"
fi

# Detect the architecture
ARCH=$(uname -m)

# Set the Rust target to use musl
case "$ARCH" in
    x86_64)
        TARGET="x86_64-unknown-linux-musl"
        ;;
    arm64)
        TARGET="aarch64-unknown-linux-musl"
        ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

docker buildx build \
    --load \
    --build-arg RUST_TARGET=$TARGET \
    -t $IMAGE_NAME $CACHING_OPTIONS "$@"
