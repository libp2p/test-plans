#!/usr/bin/env /bin/bash
set -eou pipefail
set -x

# shouldUseCache.sh - Returns exit code 0 if we don't have the image locally and we have a cache hit.

AWS_BUCKET=${AWS_BUCKET:-libp2p-by-tf-aws-bootstrap}

script_dir=$(dirname "$0")
BUILD_CACHE_KEY=$($script_dir/buildCacheKey.sh)

# If we already have this image name in docker, lets not use the cache, since a
# small change will probaby be faster than refetch the cache
if docker image inspect $IMAGE_NAME -f "{{.Id}}" &> /dev/null; then
    exit 1;
fi

curl --fail --head https://s3.amazonaws.com/$AWS_BUCKET/imageCache/$BUILD_CACHE_KEY.tar.gz &> /dev/null
# We need to echo something so that Make sees this as a target
echo $BUILD_CACHE_KEY
