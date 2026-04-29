#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

VALIDATE_DIR="$ROOT_DIR/.runtime/validate"
CERT_DIR="$VALIDATE_DIR/certs"
mkdir -p "$VALIDATE_DIR"

echo "Rendering configs from .env.example..."
./scripts/render-config.sh \
  --env-file "$ROOT_DIR/.env.example" \
  --output "$VALIDATE_DIR/gost.yml" \
  --client-output "$VALIDATE_DIR/client-h2.yml" >/dev/null

echo "Running config rendering tests..."
./tests/render-config-upstream-type.sh >/dev/null

echo "Generating disposable validation certificates..."
CERT_DIR="$CERT_DIR" TLS_SERVER_NAME=proxy.local ./scripts/generate-certs.sh --force --quiet

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "Validating Docker Compose configuration..."
  docker compose --env-file .env.example config >/dev/null

  echo "Validating GOST YAML parsing through the Docker image..."
  image=${GOST_IMAGE:-gogost/gost:latest}
  docker run --rm \
    -v "$VALIDATE_DIR/gost.yml:/etc/gost/gost.yml:ro" \
    -v "$CERT_DIR:/etc/gost/certs:ro" \
    "$image" -C /etc/gost/gost.yml -O yaml >/dev/null
else
  echo "Docker Compose is not available; skipped Compose and GOST image validation." >&2
fi

echo "Checking that secret-bearing generated files are ignored..."
git check-ignore -q .env
git check-ignore -q .runtime/gost.yml
git check-ignore -q certs/server.key
git check-ignore -q certs/ca.key

echo "Validation completed."
