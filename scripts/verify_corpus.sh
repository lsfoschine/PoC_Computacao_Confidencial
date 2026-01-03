#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${1:-data/corpus.sha256}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Hash nao encontrado: $MANIFEST" >&2
  exit 1
fi

sha256sum -c "$MANIFEST"
