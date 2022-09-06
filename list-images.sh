#!/usr/bin/env bash

LABEL="$1"
IMAGES=""

# TODO: drop empty lines
while read image; do
    if [ -z "$image" ]; then
        continue;
    fi
    HISTORY=$(docker history -q $image | grep -v '<missing>')
    IMAGES="${IMAGES} ${image} ${HISTORY}"
done <<< $(docker images --filter "label=${LABEL}" -q)

echo $IMAGES | tr ' ' '\n' | sort -u >&1