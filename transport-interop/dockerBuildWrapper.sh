#!/usr/bin/env /bin/bash

CACHING_OPTIONS=""
# Use local cache if CACHE_DIR is set, otherwise fall back to S3 if AWS_BUCKET is set
if [[ -n "${CACHE_DIR}" ]]; then
    # Create the buildCache directory if it doesn't exist
    mkdir -p "${CACHE_DIR}/buildCache/${IMAGE_NAME}"
    CACHING_OPTIONS="\
        --cache-to   type=local,mode=max,dest=${CACHE_DIR}/buildCache/${IMAGE_NAME} \
        --cache-from type=local,src=${CACHE_DIR}/buildCache/${IMAGE_NAME}"
elif [[ -n "${CI}" ]] && [[ -n "${AWS_BUCKET}" ]]; then
    CACHING_OPTIONS="\
        --cache-to   type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME \
        --cache-from type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME"
fi

docker buildx build \
    --progress=plain \
    --load \
    -t $IMAGE_NAME $CACHING_OPTIONS "$@"
