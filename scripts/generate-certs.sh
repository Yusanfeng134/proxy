#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
CERT_DIR=${CERT_DIR:-"$ROOT_DIR/certs"}
FORCE=0
QUIET=0

usage() {
  cat <<'USAGE'
Usage: scripts/generate-certs.sh [--force] [--quiet]

Generates a local CA and a server certificate for the GOST h2 tunnel.
The private keys stay in certs/ and are ignored by Git.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
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

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

TLS_SERVER_NAME=${TLS_SERVER_NAME:-proxy.local}
mkdir -p "$CERT_DIR" "$ROOT_DIR/.runtime"

if [ "$FORCE" -ne 1 ] && { [ -f "$CERT_DIR/ca.crt" ] || [ -f "$CERT_DIR/server.crt" ] || [ -f "$CERT_DIR/server.key" ]; }; then
  echo "Certificate files already exist in $CERT_DIR. Use --force to replace them." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate certificates." >&2
  exit 1
fi

openssl_conf="$ROOT_DIR/.runtime/openssl-server.cnf"
cat > "$openssl_conf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
CN = $TLS_SERVER_NAME

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $TLS_SERVER_NAME
EOF

openssl genrsa -out "$CERT_DIR/ca.key" 4096 >/dev/null 2>&1
openssl req -x509 -new -nodes \
  -key "$CERT_DIR/ca.key" \
  -sha256 \
  -days 3650 \
  -subj "/CN=$TLS_SERVER_NAME local CA" \
  -out "$CERT_DIR/ca.crt" >/dev/null 2>&1

openssl genrsa -out "$CERT_DIR/server.key" 2048 >/dev/null 2>&1
openssl req -new \
  -key "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.csr" \
  -config "$openssl_conf" >/dev/null 2>&1
openssl x509 -req \
  -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca.crt" \
  -CAkey "$CERT_DIR/ca.key" \
  -CAserial "$CERT_DIR/ca.srl" \
  -CAcreateserial \
  -out "$CERT_DIR/server.crt" \
  -days 825 \
  -sha256 \
  -extensions v3_req \
  -extfile "$openssl_conf" >/dev/null 2>&1

rm -f "$CERT_DIR/server.csr" "$CERT_DIR/ca.srl" "$ROOT_DIR/.srl"
chmod 600 "$CERT_DIR/ca.key" "$CERT_DIR/server.key"
chmod 644 "$CERT_DIR/ca.crt" "$CERT_DIR/server.crt"

if [ "$QUIET" -ne 1 ]; then
  echo "Generated certificates in $CERT_DIR"
  echo "Copy $CERT_DIR/ca.crt to domestic clients that use the h2 tunnel."
fi
