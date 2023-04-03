#!/usr/bin/env /bin/bash
set -eou pipefail
set -x

BUILD_CONTEXT="${@: -1}"
if [[ ! -d "$BUILD_CONTEXT" ]]; then
    echo "Error: Last argument must be a directory"
    exit 1
fi

REST_ARGS="${@:1:$#-1}" # All arguments except the last one

# Print the hash of the build context. This is our input hash.
# We'll use this to store the build cache in S3.
INPUT_HASH=$(tar --sort=name \
      --mtime="1970-01-01 00:00Z" \
      --owner=0 --group=0 \
      --directory $BUILD_CONTEXT \
      -cvf - . | sha256sum | sed 's/.$//' | xargs) # Sed removes the trailing dash, xargs removes the spaces

# Add the arguments to the hash, so we have a different cache key if args change.
INPUT_HASH=$(echo "$INPUT_HASH $REST_ARGS" | sha256sum | sed 's/.$//' | xargs)

ARCH=$(docker info -f "{{.Architecture}}")

# Get the dockerfile from the arguments, it's either -f or --file
DOCKERFILE=$(echo "$REST_ARGS" | grep -oE "(-f|--file) [^ ]*") || echo ""
if [[ -z "$DOCKERFILE" ]]; then
    # If no dockerfile is specified, use the default
    DOCKERFILE="Dockerfile"
else
    DOCKERFILE=$(echo "$DOCKERFILE" | cut -d' ' -f2)
fi

DOCKERFILE_PATH=$(readlink -f "$DOCKERFILE")
BUILD_CONTEXT_PATH=$(readlink -f $BUILD_CONTEXT)
if [[ -f "$DOCKERFILE_PATH" ]]; then
    case $DOCKERFILE_PATH in
    $BUILD_CONTEXT_PATH/*)
        # Dockerfile is within the build context, so it's covered under the
        # build context hash
        ;;
    *)
        # Dockerfile is outside the build context. Let's add its contents to the hash
        INPUT_HASH=$(cat $DOCKERFILE_PATH  | cat - <(echo " # context_hash = $INPUT_HASH")  | sha256sum | sed 's/.$//' | xargs) ;;
    esac

    echo "Dockerfile is: $DOCKERFILE_PATH, cwd is: $BUILD_CONTEXT_PATH"
else
    echo "Error: Dockerfile not found"
    exit 1
fi

BUILD_HASH="$IMAGE_NAME-$INPUT_HASH-$ARCH"
echo "Build hash is: $BUILD_HASH"

# If we don't have this image, and we have an S3 bucket defined, try to load it from S3.
# If we have this image, it's probably faster to rebuild the parts that have changed rather than fetch from S3.
if (! docker image inspect $IMAGE_NAME -f "{{.Id}}") && [[ -n "${AWS_BUCKET:-}" ]]; then
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
    -t $IMAGE_NAME $CACHING_OPTIONS $REST_ARGS $BUILD_CONTEXT

# If we're in CI, let's save the image to S3
# Check if CI is set, and if we have an S3 bucket defined

if   [[ -n "${CI:-}" ]] && [[ -n "${AWS_BUCKET:-}" ]]; then
    echo "Saving image to S3"
    docker image save $IMAGE_NAME | gzip | aws s3 cp - s3://$AWS_BUCKET/imageCache/$BUILD_HASH.tar.gz
fi
