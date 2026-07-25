#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

hash_one() {
  local corpus_path="$1"
  local out_path="$2"

  if [[ ! -f "$corpus_path" ]]; then
    echo "Corpus nao encontrado: $corpus_path" >&2
    exit 1
  fi

  sha256sum "$corpus_path" >"$out_path"
  echo "Wrote $out_path"
}

if [[ $# -gt 0 ]]; then
  hash_one "$1" "${2:-${1}.sha256}"
else
  hash_one "data/corpus.jsonl" "data/corpus.sha256"
  hash_one "data/warmup.jsonl" "data/warmup.sha256"
fi
