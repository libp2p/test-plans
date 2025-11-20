#!/bin/bash
# Build Docker images for all implementations defined in impls.yaml
# Uses content-addressed caching under $CACHE_DIR/snapshots/

set -euo pipefail

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
FILTER="${1:-}"  # Optional: filter to specific impl (e.g., "rust")

echo "Building Docker images..."
echo "Cache directory: $CACHE_DIR"
echo ""

# Ensure cache directory exists
mkdir -p "$CACHE_DIR/snapshots"

# Parse impls.yaml and build each implementation
impl_count=$(yq eval '.implementations | length' impls.yaml)

for ((i=0; i<impl_count; i++)); do
    # Extract implementation details
    impl_id=$(yq eval ".implementations[$i].id" impls.yaml)
    repo=$(yq eval ".implementations[$i].source.repo" impls.yaml)
    commit=$(yq eval ".implementations[$i].source.commit" impls.yaml)
    dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)

    # Apply filter if specified
    if [ -n "$FILTER" ] && [[ ! "$impl_id" =~ $FILTER ]]; then
        echo "⊘ Skipping $impl_id (filtered out)"
        continue
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building: $impl_id"
    echo "  Repo: $repo"
    echo "  Commit: ${commit:0:8}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    snapshot_file="$CACHE_DIR/snapshots/$commit.zip"

    # Download snapshot if not cached
    if [ ! -f "$snapshot_file" ]; then
        echo "→ Downloading snapshot..."
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
        echo "  ✓ Cached: ${commit:0:8}.zip"
    else
        echo "→ Using cached snapshot: ${commit:0:8}.zip"
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
    if ! docker build -f "$extracted_dir/$dockerfile" -t "$impl_id" "$extracted_dir" 2>&1 | grep -E "^(Step|Successfully|ERROR)"; then
        echo "✗ Docker build failed"
        exit 1
    fi

    # Get image ID (strip sha256: prefix)
    image_id=$(docker image inspect "$impl_id" -f '{{.Id}}' | cut -d':' -f2)

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
imageName: $impl_id
builtAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
arch: $(uname -m)
snapshot: snapshots/$commit.zip
commit: $commit
repo: $repo
EOF

    echo "  ✓ Generated: $image_yaml"
    echo "  ✓ Image ID: ${image_id:0:12}..."
    echo ""

    # Clean up
    rm -rf "$work_dir"
    trap - EXIT
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ All images built successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
