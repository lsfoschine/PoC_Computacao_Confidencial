#!/usr/bin/env bash
set -euo pipefail

CORPUS_PATH="${1:-data/corpus.jsonl}"
OUT_PATH="${2:-data/corpus.sha256}"

if [[ ! -f "$CORPUS_PATH" ]]; then
  echo "Corpus nao encontrado: $CORPUS_PATH" >&2
  exit 1
fi

sha256sum "$CORPUS_PATH" > "$OUT_PATH"

echo "Wrote $OUT_PATH"
