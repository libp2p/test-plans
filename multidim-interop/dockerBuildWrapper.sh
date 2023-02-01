#!/usr/bin/env /bin/bash

# TODO replace bucket name here

# If in CI use caching
if [[ -n "${CI}" ]]; then
    docker buildx build \
    --load \
    -t $IMAGE_NAME \
    --cache-to   type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME \
    --cache-from type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME \
    "$@"
else
	docker build -t $IMAGE_NAME "$@"
fi

