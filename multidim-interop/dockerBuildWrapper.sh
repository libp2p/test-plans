#!/usr/bin/env /bin/bash

# If in CI use caching
if [[ -n "${CI}" ]]; then
    docker buildx build \
    --load \
    -t $IMAGE_NAME \
    --cache-to type=gha,mode=max,scope=$GITHUB_REF_NAME-$IMAGE_NAME \
    --cache-from type=gha,scope=$GITHUB_REF_NAME-$IMAGE_NAME "$@"
else
	docker build -t $IMAGE_NAME "$@"
fi

