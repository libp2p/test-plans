#!/usr/bin/env bash
# Build (or retag) the Python interop image so its name matches what
# versions.ts derives from versionsInput.json (GHCR base + content-hash tag).
# With that tag present locally, `npm run test` uses your image and does not
# need versionsInput.local.json.
#
# Run from this directory (impl/python/v0.x) or via npm run build:python-image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TI_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPO_ROOT="$(cd "${TI_ROOT}/.." && pwd)"
CONTEXT="${SCRIPT_DIR}"
DOCKERFILE="${CONTEXT}/Dockerfile"

usage() {
  echo "Usage: $0 [--tag-only]"
  echo ""
  echo "  (default)  docker buildx build this directory's context and tag as the"
  echo "             resolved GHCR name (same tag versions.ts appends for python-v0.x)."
  echo ""
  echo "  --tag-only If image 'python-v0.x' already exists (e.g. after make),"
  echo "             only run: docker tag python-v0.x <resolved-ghcr-name>"
  echo ""
  echo "Prepare sources first when building from scratch, e.g.:"
  echo "  make -C ${CONTEXT}"
  exit "${1:-0}"
}

TAG_ONLY=false
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
fi
if [[ "${1:-}" == "--tag-only" ]]; then
  TAG_ONLY=true
  shift || true
fi
if [[ -n "${1:-}" ]]; then
  usage 1
fi

KEY="$(node "${REPO_ROOT}/.github/scripts/compute-cache-key.mjs" python v0.x)"
IMAGE_REF="ghcr.io/libp2p/test-plans/transport-interop/python-v0.x:${KEY}"

echo "Resolved image (matches default versionsInput.json + versions.ts):"
echo "  ${IMAGE_REF}"
echo

if [[ "${TAG_ONLY}" == true ]]; then
  if ! docker image inspect python-v0.x &>/dev/null; then
    echo "error: no local image 'python-v0.x'. Run: make -C ${CONTEXT}"
    echo "       then: $0 --tag-only"
    exit 1
  fi
  docker tag python-v0.x "${IMAGE_REF}"
  echo "Tagged python-v0.x -> ${IMAGE_REF}"
else
  docker buildx build --load -f "${DOCKERFILE}" -t "${IMAGE_REF}" "${CONTEXT}"
  echo "Built ${IMAGE_REF}"
fi

echo "You can run interop tests without versionsInput.local.json (delete it if present)."
