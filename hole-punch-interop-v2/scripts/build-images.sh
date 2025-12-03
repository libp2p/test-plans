#!/bin/bash
# Build Docker images for all implementations defined in impls.yaml
# Uses content-addressed caching under $CACHE_DIR/snapshots/

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
FILTER="${1:-}"  # Optional: filter to specific impl (e.g., "rust")
FORCE_REBUILD="${2:-false}"  # Optional: force rebuild all images

echo "  → Cache directory: $CACHE_DIR"
[ -n "$FILTER" ] && echo "  → Filter: $FILTER"
[ "$FORCE_REBUILD" = "true" ] && echo "  → Force rebuild: enabled"

# Ensure cache directory exists
mkdir -p "$CACHE_DIR/snapshots"

# Function to build a single image from repo
build_image_from_source() {
    local image_name="$1"
    local repo="$2"
    local commit="$3"
    local dockerfile="$4"
    local build_context="${5:-$dockerfile}"  # Default to dockerfile path if not specified

    # Check if image already exists (skip if not forcing rebuild)
    if [ "$FORCE_REBUILD" = "false" ] && docker image inspect "$image_name" &>/dev/null; then
        echo "  ✓ $image_name (already built)"
        return 0
    fi

    echo ""
    echo "╲ Building: $image_name"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "→ Repo: $repo"
    echo "→ Commit: ${commit:0:8}"

    snapshot_file="$CACHE_DIR/snapshots/$commit.zip"

    # Download snapshot if not cached
    if [ ! -f "$snapshot_file" ]; then
        echo "  → [MISS] Downloading snapshot..."
        repo_url="https://github.com/$repo/archive/$commit.zip"
        wget -q -O "$snapshot_file" "$repo_url" || {
            echo "✗ Failed to download snapshot"
            return 1
        }

        # Create metadata file
        cat > "$snapshot_file.metadata" <<EOF
url: $repo_url
downloadedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
size: $(stat -f%z "$snapshot_file" 2>/dev/null || stat -c%s "$snapshot_file")
repo: $repo
commit: $commit
EOF
        echo "  ✓ Added to cache: ${commit:0:8}.zip"
    else
        echo "  ✓ [HIT] Using cached snapshot: ${commit:0:8}.zip"
    fi

    # Extract snapshot to temporary directory
    work_dir=$(mktemp -d)
    trap "rm -rf $work_dir" EXIT

    echo "→ Extracting snapshot..."
    unzip -q "$snapshot_file" -d "$work_dir"

    # Find extracted directory (GitHub archives are named repo-commit)
    repo_name=$(basename "$repo")
    extracted_dir="$work_dir/$repo_name-$commit"

    if [ ! -d "$extracted_dir" ]; then
        echo "✗ Expected directory not found: $extracted_dir"
        ls -la "$work_dir"
        rm -rf "$work_dir"
        trap - EXIT
        return 1
    fi

    # Determine build context directory
    local context_dir="$extracted_dir"
    if [ "$build_context" != "$dockerfile" ]; then
        # If build context is different from dockerfile location, use it
        context_dir="$extracted_dir/$(dirname "$build_context")"
    fi

    # Build Docker image
    echo "→ Building Docker image..."
    echo "→ Command: docker build -f $extracted_dir/$dockerfile -t $image_name $context_dir"
    if ! docker build -f "$extracted_dir/$dockerfile" -t "$image_name" "$context_dir" 2>&1 | grep -E "^(#|Step|Successfully|ERROR)"; then
        echo "✗ Docker build failed"
        rm -rf "$work_dir"
        trap - EXIT
        return 1
    fi

    echo "✓ Built: $image_name"

    # Clean up
    rm -rf "$work_dir"
    trap - EXIT
}

# Build relay images if needed
build_relay_images() {
    local relay_count=$(yq eval '.relays | length' impls.yaml)

    for ((i=0; i<relay_count; i++)); do
        local relay_id=$(yq eval ".relays[$i].id" impls.yaml)
        local relay_image="hole-punch-relay-${relay_id}"
        local relay_type=$(yq eval ".relays[$i].source.type" impls.yaml)

        # Check if image already exists (skip if not forcing rebuild)
        if [ "$FORCE_REBUILD" = "false" ] && docker image inspect "$relay_image" &>/dev/null; then
            echo "  ✓ $relay_image (already built)"
            continue
        fi

        echo ""
        echo "╲ Building relay: $relay_id ($relay_image)"
        echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

        if [ "$relay_type" = "local" ]; then
            local relay_path=$(yq eval ".relays[$i].source.path" impls.yaml)
            local relay_dockerfile=$(yq eval ".relays[$i].source.dockerfile" impls.yaml)

            echo "→ Building from local path: $relay_path"
            echo "→ Command: docker build -f $relay_path/$relay_dockerfile -t $relay_image $relay_path"

            if ! docker build -f "$relay_path/$relay_dockerfile" -t "$relay_image" "$relay_path" 2>&1 | grep -E "^(#|Step|Successfully|ERROR)"; then
                echo "✗ Docker build failed"
                return 1
            fi

            echo "✓ Built: $relay_image"
        else
            local relay_repo=$(yq eval ".relays[$i].source.repo" impls.yaml)
            local relay_commit=$(yq eval ".relays[$i].source.commit" impls.yaml)
            local relay_dockerfile=$(yq eval ".relays[$i].source.dockerfile" impls.yaml)
            local relay_context=$(yq eval ".relays[$i].source.buildContext" impls.yaml)

            build_image_from_source "$relay_image" "$relay_repo" "$relay_commit" "$relay_dockerfile" "$relay_context"
        fi
    done
}

# Build router images if needed
build_router_images() {
    local router_count=$(yq eval '.routers | length' impls.yaml)

    for ((i=0; i<router_count; i++)); do
        local router_id=$(yq eval ".routers[$i].id" impls.yaml)
        local router_image="hole-punch-router-${router_id}"
        local router_type=$(yq eval ".routers[$i].source.type" impls.yaml)

        # Check if image already exists (skip if not forcing rebuild)
        if [ "$FORCE_REBUILD" = "false" ] && docker image inspect "$router_image" &>/dev/null; then
            echo "  ✓ $router_image (already built)"
            continue
        fi

        echo ""
        echo "╲ Building router: $router_id ($router_image)"
        echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

        if [ "$router_type" = "local" ]; then
            local router_path=$(yq eval ".routers[$i].source.path" impls.yaml)
            local router_dockerfile=$(yq eval ".routers[$i].source.dockerfile" impls.yaml)

            echo "→ Building from local path: $router_path"
            echo "→ Command: docker build -f $router_path/$router_dockerfile -t $router_image $router_path"

            if ! docker build -f "$router_path/$router_dockerfile" -t "$router_image" "$router_path" 2>&1 | grep -E "^(#|Step|Successfully|ERROR)"; then
                echo "✗ Docker build failed"
                return 1
            fi

            echo "✓ Built: $router_image"
        else
            local router_repo=$(yq eval ".routers[$i].source.repo" impls.yaml)
            local router_commit=$(yq eval ".routers[$i].source.commit" impls.yaml)
            local router_dockerfile=$(yq eval ".routers[$i].source.dockerfile" impls.yaml)
            local router_context=$(yq eval ".routers[$i].source.buildContext" impls.yaml)

            build_image_from_source "$router_image" "$router_repo" "$router_commit" "$router_dockerfile" "$router_context"
        fi
    done
}

# Build relays and routers first
build_relay_images
build_router_images

# Parse impls.yaml and build each implementation
impl_count=$(yq eval '.implementations | length' impls.yaml)

for ((i=0; i<impl_count; i++)); do
    # Extract implementation details
    impl_id=$(yq eval ".implementations[$i].id" impls.yaml)
    impl_image="hole-punch-peer-${impl_id}"
    source_type=$(yq eval ".implementations[$i].source.type" impls.yaml)

    # Apply filter if specified (exact match with anchors)
    if [ -n "$FILTER" ] && [[ ! "$impl_id" =~ ^($FILTER)$ ]]; then
        continue
    fi

    # Check if image already exists (skip if not forcing rebuild)
    if [ "$FORCE_REBUILD" = "false" ] && docker image inspect "$impl_image" &>/dev/null; then
        echo "  ✓ $impl_image (already built)"
        continue
    fi

    echo ""
    echo "╲ Building peer: $impl_id ($impl_image)"
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

    if [ "$source_type" = "local" ]; then
        impl_path=$(yq eval ".implementations[$i].source.path" impls.yaml)
        impl_dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)

        echo "→ Building from local path: $impl_path"
        echo "→ Command: docker build -f $impl_path/$impl_dockerfile -t $impl_image $impl_path"

        if ! docker build -f "$impl_path/$impl_dockerfile" -t "$impl_image" "$impl_path" 2>&1 | grep -E "^(#|Step|Successfully|ERROR)"; then
            echo "✗ Docker build failed"
            exit 1
        fi

        echo "✓ Built: $impl_image"
        continue
    fi

    # GitHub source
    repo=$(yq eval ".implementations[$i].source.repo" impls.yaml)
    commit=$(yq eval ".implementations[$i].source.commit" impls.yaml)
    dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)

    echo "→ Repo: $repo"
    echo "→ Commit: ${commit:0:8}"

    snapshot_file="$CACHE_DIR/snapshots/$commit.zip"

    # Download snapshot if not cached
    if [ ! -f "$snapshot_file" ]; then
        echo "  → [MISS] Downloading snapshot..."
        repo_url="https://github.com/$repo/archive/$commit.zip"
        wget -q -O "$snapshot_file" "$repo_url" || {
            echo "✗ Failed to download snapshot"
            exit 1
        }

        # Create metadata file
        cat > "$snapshot_file.metadata" <<EOF
url: $repo_url
downloadedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
size: $(stat -f%z "$snapshot_file" 2>/dev/null || stat -c%s "$snapshot_file")
repo: $repo
commit: $commit
EOF
        echo "  ✓ Added to cache: ${commit:0:8}.zip"
    else
        echo "  ✓ [HIT] Using cached snapshot: ${commit:0:8}.zip"
    fi

    # Extract snapshot to temporary directory
    work_dir=$(mktemp -d)
    trap "rm -rf $work_dir" EXIT

    echo "→ Extracting snapshot..."
    unzip -q "$snapshot_file" -d "$work_dir"

    # Find extracted directory (GitHub archives are named repo-commit)
    repo_name=$(basename "$repo")
    extracted_dir="$work_dir/$repo_name-$commit"

    if [ ! -d "$extracted_dir" ]; then
        echo "✗ Expected directory not found: $extracted_dir"
        ls -la "$work_dir"
        exit 1
    fi

    # Build Docker image
    echo "→ Building Docker image..."
    echo "→ Command: docker build -f $extracted_dir/$dockerfile -t $impl_image $extracted_dir"
    if ! docker build -f "$extracted_dir/$dockerfile" -t "$impl_image" "$extracted_dir" 2>&1 | grep -E "^(#|Step|Successfully|ERROR)"; then
        echo "✗ Docker build failed"
        exit 1
    fi

    # Get image ID (strip sha256: prefix)
    image_id=$(docker image inspect "$impl_image" -f '{{.Id}}' | cut -d':' -f2)

    # Generate image.yaml in impl directory
    impl_lang=$(echo "$impl_id" | cut -d'-' -f1)
    impl_version=$(echo "$impl_id" | cut -d'-' -f2)

    # Determine output location (if version directory exists)
    if [ -d "impls/$impl_lang/$impl_version" ]; then
        image_yaml="impls/$impl_lang/$impl_version/image.yaml"
    else
        # Store in impl lang directory
        image_yaml="impls/$impl_lang/image-$impl_version.yaml"
    fi

    cat > "$image_yaml" <<EOF
imageID: $image_id
imageName: $impl_image
builtAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
arch: $(uname -m)
snapshot: snapshots/$commit.zip
commit: $commit
repo: $repo
EOF

    echo "✓ Built: $impl_image"
    echo "✓ Image ID: ${image_id:0:12}..."

    # Clean up
    rm -rf "$work_dir"
    trap - EXIT
done

echo ""
echo "✓ All required images built successfully"
