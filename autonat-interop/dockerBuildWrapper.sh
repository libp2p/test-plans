#!/usr/bin/env /bin/bash

CACHING_OPTIONS=""
# If in CI and we have a defined cache bucket, use caching
if [[ -n "${CI}" ]] && [[ -n "${AWS_BUCKET}" ]]; then
    CACHING_OPTIONS="\
        --cache-to   type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME \
        --cache-from type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME"
fi

docker buildx build \
    --load \
    -t $IMAGE_NAME $CACHING_OPTIONS "$@"
