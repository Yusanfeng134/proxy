#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
SERVER_OUTPUT="$ROOT_DIR/.runtime/gost.yml"
CLIENT_OUTPUT="$ROOT_DIR/.runtime/client-h2.yml"

usage() {
  cat <<'USAGE'
Usage: scripts/render-config.sh [--env-file PATH] [--output PATH] [--client-output PATH]

Renders ignored GOST YAML files from a shell-compatible .env file.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE=$2
      shift 2
      ;;
    --output)
      SERVER_OUTPUT=$2
      shift 2
      ;;
    --client-output)
      CLIENT_OUTPUT=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE" >&2
  echo "Copy .env.example to .env and fill in real values first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

SOCKS_PORT=${SOCKS_PORT:-1080}
HTTP_PORT=${HTTP_PORT:-8080}
TUNNEL_PORT=${TUNNEL_PORT:-8443}
LOCAL_SOCKS_PORT=${LOCAL_SOCKS_PORT:-11080}
UPSTREAM_MAX_FAILS=${UPSTREAM_MAX_FAILS:-2}
UPSTREAM_FAIL_TIMEOUT=${UPSTREAM_FAIL_TIMEOUT:-30s}
TLS_SERVER_NAME=${TLS_SERVER_NAME:-proxy.local}
SERVER_HOST=${SERVER_HOST:-127.0.0.1}
CLIENT_CA_FILE=${CLIENT_CA_FILE:-./ca.crt}
GOST_LOG_LEVEL=${GOST_LOG_LEVEL:-info}

required_vars='PUBLIC_USER PUBLIC_PASS UPSTREAM_1_HOST UPSTREAM_1_PORT UPSTREAM_1_USER UPSTREAM_1_PASS UPSTREAM_2_HOST UPSTREAM_2_PORT UPSTREAM_2_USER UPSTREAM_2_PASS'
missing=''
for var in $required_vars; do
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then
    missing="$missing $var"
  fi
done

if [ -n "$missing" ]; then
  echo "Missing required env vars:$missing" >&2
  exit 1
fi

newline='
'
string_vars='PUBLIC_USER PUBLIC_PASS UPSTREAM_1_HOST UPSTREAM_1_USER UPSTREAM_1_PASS UPSTREAM_2_HOST UPSTREAM_2_USER UPSTREAM_2_PASS TLS_SERVER_NAME SERVER_HOST CLIENT_CA_FILE GOST_LOG_LEVEL'
for var in $string_vars; do
  eval "value=\${$var:-}"
  case "$value" in
    *"$newline"*)
      echo "$var must not contain a newline." >&2
      exit 1
      ;;
  esac
done

is_port() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

for port_var in SOCKS_PORT HTTP_PORT TUNNEL_PORT LOCAL_SOCKS_PORT UPSTREAM_1_PORT UPSTREAM_2_PORT; do
  eval "port_value=\${$port_var}"
  if ! is_port "$port_value"; then
    echo "$port_var must be an integer between 1 and 65535." >&2
    exit 1
  fi
done

case "$UPSTREAM_MAX_FAILS" in
  ''|*[!0-9]*)
    echo "UPSTREAM_MAX_FAILS must be a non-negative integer." >&2
    exit 1
    ;;
esac

if ! printf '%s' "$UPSTREAM_FAIL_TIMEOUT" | grep -Eq '^[0-9]+(ms|s|m|h)$'; then
  echo "UPSTREAM_FAIL_TIMEOUT must look like 30s, 5m, or 1h." >&2
  exit 1
fi

for host_var in UPSTREAM_1_HOST UPSTREAM_2_HOST; do
  eval "host_value=\${$host_var}"
  case "$host_value" in
    *://*)
      echo "$host_var should be only a hostname or IP, not a URL." >&2
      exit 1
      ;;
  esac
done

yaml_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/'
}

server_dir=$(dirname -- "$SERVER_OUTPUT")
client_dir=$(dirname -- "$CLIENT_OUTPUT")
mkdir -p "$server_dir" "$client_dir"

cat > "$SERVER_OUTPUT" <<EOF
services:
  - name: public-socks5
    addr: ":$SOCKS_PORT"
    handler:
      type: socks5
      auth:
        username: $(yaml_quote "$PUBLIC_USER")
        password: $(yaml_quote "$PUBLIC_PASS")
      chain: residential-upstreams
    listener:
      type: tcp

  - name: public-http
    addr: ":$HTTP_PORT"
    handler:
      type: http
      auth:
        username: $(yaml_quote "$PUBLIC_USER")
        password: $(yaml_quote "$PUBLIC_PASS")
      chain: residential-upstreams
    listener:
      type: tcp

  - name: public-socks5-h2
    addr: ":$TUNNEL_PORT"
    handler:
      type: socks5
      auth:
        username: $(yaml_quote "$PUBLIC_USER")
        password: $(yaml_quote "$PUBLIC_PASS")
      chain: residential-upstreams
    listener:
      type: h2
      tls:
        certFile: /etc/gost/certs/server.crt
        keyFile: /etc/gost/certs/server.key

chains:
  - name: residential-upstreams
    hops:
      - name: residential-socks5-hop
        selector:
          strategy: round
          maxFails: $UPSTREAM_MAX_FAILS
          failTimeout: $UPSTREAM_FAIL_TIMEOUT
        nodes:
          - name: residential-a
            addr: $(yaml_quote "$UPSTREAM_1_HOST:$UPSTREAM_1_PORT")
            connector:
              type: socks5
              auth:
                username: $(yaml_quote "$UPSTREAM_1_USER")
                password: $(yaml_quote "$UPSTREAM_1_PASS")
            dialer:
              type: tcp
          - name: residential-b
            addr: $(yaml_quote "$UPSTREAM_2_HOST:$UPSTREAM_2_PORT")
            connector:
              type: socks5
              auth:
                username: $(yaml_quote "$UPSTREAM_2_USER")
                password: $(yaml_quote "$UPSTREAM_2_PASS")
            dialer:
              type: tcp

log:
  output: stderr
  level: $(yaml_quote "$GOST_LOG_LEVEL")
  format: text
EOF

cat > "$CLIENT_OUTPUT" <<EOF
services:
  - name: local-socks5-to-overseas-h2
    addr: "127.0.0.1:$LOCAL_SOCKS_PORT"
    handler:
      type: socks5
      chain: overseas-h2-tunnel
    listener:
      type: tcp

chains:
  - name: overseas-h2-tunnel
    hops:
      - name: overseas-h2-hop
        nodes:
          - name: overseas-relay
            addr: $(yaml_quote "$SERVER_HOST:$TUNNEL_PORT")
            connector:
              type: socks5
              auth:
                username: $(yaml_quote "$PUBLIC_USER")
                password: $(yaml_quote "$PUBLIC_PASS")
            dialer:
              type: h2
              tls:
                secure: true
                serverName: $(yaml_quote "$TLS_SERVER_NAME")
                caFile: $(yaml_quote "$CLIENT_CA_FILE")
EOF

chmod 600 "$SERVER_OUTPUT" "$CLIENT_OUTPUT"
echo "Rendered server config: $SERVER_OUTPUT"
echo "Rendered client tunnel config: $CLIENT_OUTPUT"
