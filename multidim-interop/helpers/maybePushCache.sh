#!/usr/bin/env /bin/bash
set -eou pipefail
set -x

if [[ -n "${PUSH_CACHE:-}" ]]; then 
    script_dir=$(dirname "$0")
    BUILD_CACHE_KEY=$($script_dir/buildCacheKey.sh)
    AWS_BUCKET=${AWS_BUCKET:-libp2p-by-tf-aws-bootstrap}

    docker image save $IMAGE_NAME | gzip | aws s3 cp - s3://$AWS_BUCKET/imageCache/$BUILD_CACHE_KEY.tar.gz
fi

