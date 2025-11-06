#!/usr/bin/env bash
set -euo pipefail

cd /workspace

if [[ ! -x ./scripts/bootstrap.sh ]]; then
  echo "Bootstrap script not found."
  exit 1
fi

chmod +x ./scripts/bootstrap.sh ./scripts/start-all.sh 2>/dev/null || true

./scripts/bootstrap.sh --install-only
