#!/usr/bin/env bash
# Build + tag the agent-coordinator image, content-addressed by its Dockerfile (same Dockerfile → the
# same tag). Mirrors the CI workflow (.github/workflows/build-image.yaml) so `local == CI`. CI is the
# normal path (every push to master builds + pushes); this is the manual/escape-hatch mirror.
#
#   bash scripts/build-image.sh             # build only (needs docker)
#   PUSH=true bash scripts/build-image.sh   # build + push (after `docker login ghcr.io`)
set -euo pipefail
cd "$(dirname "$0")/.."

REGISTRY="${REGISTRY:-ghcr.io/teststuffstash}"
IMAGE="$REGISTRY/agent-coordinator"
DOCKERHASH="$(sha256sum coordinator/Dockerfile | cut -c1-8)"
TAG="$(date -u +%Y-%m-%d)-${DOCKERHASH}"

echo "→ building $IMAGE:$TAG (+ :latest)"
docker build -f coordinator/Dockerfile -t "$IMAGE:$TAG" -t "$IMAGE:latest" .

if [ "${PUSH:-false}" = "true" ]; then
  docker push "$IMAGE:$TAG"
  docker push "$IMAGE:latest"
fi

echo "→ done. tag=$TAG  push=${PUSH:-false}"
