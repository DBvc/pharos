#!/usr/bin/env bash
set -euo pipefail
curl -s -X POST http://127.0.0.1:8765/v0/capture \
  -H 'content-type: application/json' \
  -d @examples/manual_capture.json | jq
