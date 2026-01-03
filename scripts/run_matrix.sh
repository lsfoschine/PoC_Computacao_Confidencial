#!/usr/bin/env bash
set -euo pipefail

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"

DEFAULT_SEQ_LENS=(256 512 1024 2048)
DEFAULT_BATCH_SIZES=(4 8 16)

if [[ -n "${SEQ_LENS:-}" ]]; then
  read -r -a SEQ_LENS_ARR <<< "${SEQ_LENS}"
else
  SEQ_LENS_ARR=("${DEFAULT_SEQ_LENS[@]}")
fi

if [[ -n "${BATCH_SIZES:-}" ]]; then
  read -r -a BATCH_SIZES_ARR <<< "${BATCH_SIZES}"
else
  BATCH_SIZES_ARR=("${DEFAULT_BATCH_SIZES[@]}")
fi

LIMIT_ARG=()
if [[ -n "${LIMIT:-}" ]]; then
  LIMIT_ARG=(--limit "${LIMIT}")
fi

for seq_len in "${SEQ_LENS_ARR[@]}"; do
  for batch_size in "${BATCH_SIZES_ARR[@]}"; do
    printf "\n== seq_len=%s batch=%s ==\n" "$seq_len" "$batch_size"
    uv run python src/bench_embed.py --seq-len "$seq_len" --batch-size "$batch_size" "${LIMIT_ARG[@]}"
  done
done

uv run python - <<'PY'
import csv
import json
from pathlib import Path

run_path = Path("results/run.jsonl")
summary_path = Path("results/summary.csv")

if not run_path.exists():
    raise SystemExit("results/run.jsonl nao encontrado")

rows = []
with run_path.open("r", encoding="utf-8") as handle:
    for line in handle:
        if not line.strip():
            continue
        rows.append(json.loads(line))

fieldnames = [
    "timestamp",
    "model",
    "seq_len",
    "batch_size",
    "num_docs",
    "p50_ms",
    "p95_ms",
    "docs_per_s",
    "total_s",
]

with summary_path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") for key in fieldnames})

print(f"Wrote {summary_path}")
PY
