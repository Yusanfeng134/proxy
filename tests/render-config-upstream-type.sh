#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

ENV_FILE="$TMP_DIR/.env"
SERVER_OUTPUT="$TMP_DIR/gost.yml"
CLIENT_OUTPUT="$TMP_DIR/client-h2.yml"

cp "$ROOT_DIR/.env.example" "$ENV_FILE"
sed -i.bak 's/^UPSTREAM_1_HOST=.*/UPSTREAM_1_HOST=proxy-a.example.com/' "$ENV_FILE"
sed -i.bak 's/^UPSTREAM_2_HOST=.*/UPSTREAM_2_HOST=proxy-b.example.com/' "$ENV_FILE"
{
  echo 'UPSTREAM_1_TYPE=http'
  echo 'UPSTREAM_2_TYPE=http'
} >> "$ENV_FILE"

"$ROOT_DIR/scripts/render-config.sh" \
  --env-file "$ENV_FILE" \
  --output "$SERVER_OUTPUT" \
  --client-output "$CLIENT_OUTPUT" >/dev/null

if ! awk '
  /name: residential-a/ { in_node = 1 }
  in_node && /connector:/ { in_connector = 1 }
  in_connector && /type: http/ { found = 1 }
  /name: residential-b/ { exit }
  END { exit found ? 0 : 1 }
' "$SERVER_OUTPUT"; then
  echo "Expected residential-a connector type to render as http." >&2
  exit 1
fi

if ! awk '
  /name: residential-b/ { in_node = 1 }
  in_node && /connector:/ { in_connector = 1 }
  in_connector && /type: http/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$SERVER_OUTPUT"; then
  echo "Expected residential-b connector type to render as http." >&2
  exit 1
fi

echo "Upstream connector type rendering OK."
