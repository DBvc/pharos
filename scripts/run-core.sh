#!/usr/bin/env bash
set -euo pipefail
: "${PHAROS_CAPABILITY_TOKEN:?Set PHAROS_CAPABILITY_TOKEN to a runtime-only value before starting pharosd}"
if [[ ! "$PHAROS_CAPABILITY_TOKEN" =~ ^[0-9a-f]{64}$ ]]; then
  echo "PHAROS_CAPABILITY_TOKEN must be exactly 64 lowercase hexadecimal characters" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/var"
cd "$ROOT/core"
export PHAROS_DB="${PHAROS_DB:-$ROOT/var/pharos.dev.sqlite}"
export PHAROS_HOST="${PHAROS_HOST:-127.0.0.1}"
export PHAROS_PORT="${PHAROS_PORT:-8765}"
echo "Starting pharosd on $PHAROS_HOST:$PHAROS_PORT"
echo "Database: $PHAROS_DB"
dune exec pharosd -- --db "$PHAROS_DB" --host "$PHAROS_HOST" --port "$PHAROS_PORT"
