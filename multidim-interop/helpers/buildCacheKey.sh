#!/usr/bin/env /bin/bash
set -eou pipefail
set -x

# Assert that IMAGE_NAME is not empty
if [ -z "$IMAGE_NAME" ]; then
  echo "IMAGE_NAME is not set"
  exit 1
fi

ARCH=$(docker info -f "{{.Architecture}}")
BUILD_CACHE_KEY="$IMAGE_NAME-$CACHE_KEY-$ARCH"
echo $BUILD_CACHE_KEY
