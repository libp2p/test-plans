#!/usr/bin/env /bin/bash

docker buildx build \
    --load \
    -t $IMAGE_NAME "$@"
