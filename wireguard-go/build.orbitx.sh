#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
GOOS=linux GOARCH="${GOARCH:-amd64}" CGO_ENABLED=0 go build -trimpath -o orbitx ./cmd/orbitx
echo "Built ./orbitx"