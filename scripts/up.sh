#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo "Missing .env. Copy .env.example to .env and fill in real values first." >&2
  exit 1
fi

./scripts/render-config.sh

if [ ! -f certs/server.crt ] || [ ! -f certs/server.key ] || [ ! -f certs/ca.crt ]; then
  ./scripts/generate-certs.sh
fi

docker compose --env-file .env up -d
docker compose --env-file .env ps
