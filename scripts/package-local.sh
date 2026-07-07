#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/.."
zip -r pharos-starter.zip pharos-starter \
  -x "*/_build/*" "*/.build/*" "*/.swiftpm/*" "*/var/*.sqlite*"
echo "Created $ROOT/../pharos-starter.zip"
