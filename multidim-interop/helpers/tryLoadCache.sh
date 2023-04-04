#!/usr/bin/env /bin/bash
set -eou pipefail
set -x

script_dir=$(dirname "$0")
BUILD_CACHE_KEY=$($script_dir/buildCacheKey.sh)
AWS_BUCKET=${AWS_BUCKET:-libp2p-by-tf-aws-bootstrap}


curl  https://s3.amazonaws.com/$AWS_BUCKET/imageCache/$BUILD_CACHE_KEY.tar.gz \
  | docker image load && \
    exit 0 \
    || exit 1
