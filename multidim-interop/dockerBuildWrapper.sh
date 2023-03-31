#!/usr/bin/env /bin/bash
set -eou pipefail
set -x

# Print the hash of our current working directory.
# We'll use this to store the build cache in S3.
CWD_HASH=$(tar --sort=name \
      --mtime="1970-01-01 00:00Z" \
      --owner=0 --group=0 \
      -cvf - . | sha256sum | sed 's/.$//' | xargs) # Sed removes the trailing dash, xargs removes the spaces
ARCH=$(docker info -f "{{.Architecture}}")
BUILD_HASH="$IMAGE_NAME-$CWD_HASH-$ARCH"

echo "Build hash is: $BUILD_HASH"

# If we don't have this image, and we have an S3 bucket defined, try to load it from S3.
# If we have this image, it's probably faster to rebuild the parts that have changed rather than fetch from S3.
if (! docker image inspect $IMAGE_NAME -f "{{.Id}}") && [[ -n "${AWS_BUCKET}" ]]; then
    echo "Trying to load image from S3"
    aws s3 cp s3://$AWS_BUCKET/imageCache/$BUILD_HASH.tar.gz - | docker image load && \
        echo "Loaded image from S3" && exit 0 \
     || echo "Failed to load image from S3"
fi

# TODO maybe get rid of this caching mode
CACHING_OPTIONS=""
# If in CI and we have a defined cache bucket, use caching
# if [[ -n "${CI}" ]] && [[ -n "${AWS_BUCKET}" ]]; then
    # CACHING_OPTIONS="\
    #     --cache-to   type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME \
    #     --cache-from type=s3,mode=max,bucket=$AWS_BUCKET,region=$AWS_REGION,prefix=buildCache,name=$IMAGE_NAME"
# fi
# echo "Caching options: $CI"

docker buildx build \
    --load \
    -t $IMAGE_NAME $CACHING_OPTIONS "$@"

# If we're in CI, let's save the image to S3
if [[ -n "${CI}" ]] && [[ -n "${AWS_BUCKET}" ]]; then
    echo "Saving image to S3"
    docker image save $IMAGE_NAME | gzip | aws s3 cp - s3://$AWS_BUCKET/imageCache/$BUILD_HASH.tar.gz
fi
