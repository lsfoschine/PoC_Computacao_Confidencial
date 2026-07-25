#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

verify_one() {
  local manifest="$1"

  if [[ ! -f "$manifest" ]]; then
    echo "Hash nao encontrado: $manifest" >&2
    exit 1
  fi

  sha256sum -c "$manifest"
}

if [[ $# -gt 0 ]]; then
  verify_one "$1"
else
  verify_one "data/corpus.sha256"
  verify_one "data/warmup.sha256"
fi
