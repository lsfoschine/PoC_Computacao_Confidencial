#!/usr/bin/env bash
set -euo pipefail

# 1. Definição do Modo (Padrão: embed)
MODE="${1:-embed}" 

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"
CORPUS_PATH="${CORPUS_PATH:-data/corpus.jsonl}"

if [ -f "./scripts/verify_corpus.sh" ]; then
    ./scripts/verify_corpus.sh
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
host="$(hostname)"
gitsha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"


if [[ "$MODE" == "embed" ]]; then
    echo "====================================================="
    echo "[*] Iniciando Matriz de IA (Embeddings)..."
    
    MATRIX_RUN_ID="${MATRIX_RUN_ID:-matrix-embed-${timestamp}-${host}-${gitsha}}"
    export MATRIX_RUN_ID
    RUN_ROOT="results/${MATRIX_RUN_ID}"
    mkdir -p "${RUN_ROOT}"

    DEFAULT_MAX_LENGTHS=(256 512 1024 2048)
    DEFAULT_BATCHES=(4 8 16)

    if [[ -n "${MAX_LENGTHS:-}" ]]; then read -r -a MAX_LENGTHS_ARR <<< "${MAX_LENGTHS}"; else MAX_LENGTHS_ARR=("${DEFAULT_MAX_LENGTHS[@]}"); fi
    if [[ -n "${BATCHES:-}" ]]; then read -r -a BATCHES_ARR <<< "${BATCHES}"; else BATCHES_ARR=("${DEFAULT_BATCHES[@]}"); fi

    THREADS_ARG=()
    if [[ -n "${THREADS:-}" ]]; then THREADS_ARG=(--threads "${THREADS}"); fi
    WARMUP_ARG=()
    if [[ -n "${WARMUP_DOCS:-}" ]]; then WARMUP_ARG=(--warmup-docs "${WARMUP_DOCS}"); fi

    for max_length in "${MAX_LENGTHS_ARR[@]}"; do
        for batch in "${BATCHES_ARR[@]}"; do
            run_dir="${RUN_ROOT}/max${max_length}_b${batch}"
            printf "\n== max_length=%s batch=%s ==\n" "$max_length" "$batch"
            uv run python src/bench_embed.py \
                --corpus "${CORPUS_PATH}" \
                --outdir "${run_dir}" \
                --max-length "${max_length}" \
                --batch "${batch}" \
                "${THREADS_ARG[@]}" \
                "${WARMUP_ARG[@]}"
        done
    done


elif [[ "$MODE" == "fabric" ]]; then
    echo "====================================================="
    echo "[*] Iniciando Matriz de Blockchain..."
    
    MATRIX_RUN_ID="${MATRIX_RUN_ID:-matrix-fabric-${timestamp}-${host}-${gitsha}}"
    export MATRIX_RUN_ID
    RUN_ROOT="results/${MATRIX_RUN_ID}"
    mkdir -p "${RUN_ROOT}"


    echo "-----------------------------------------------------"
    echo "[!] FASE DE WARMUP: Estabilizando ambiente (20 TPS)..."
    WARMUP_DIR="results/warmup_tmp"
    mkdir -p "${WARMUP_DIR}"
    
    node src/bench_fabric_direct.js \
        --corpus "${CORPUS_PATH}" \
        --outdir "${WARMUP_DIR}" \
        --tps 20 

    rm -rf "${WARMUP_DIR}" 
    echo "[✓] Warmup concluído. Aguardando 10s para estabilização térmica..."
    sleep 10
    echo "-----------------------------------------------------"

    DEFAULT_TARGET_TPS=(100 200 300 400 500 600)

    if [[ -n "${TARGET_TPS:-}" ]]; then read -r -a TPS_ARR <<< "${TARGET_TPS}"; else TPS_ARR=("${DEFAULT_TARGET_TPS[@]}"); fi

    for tps in "${TPS_ARR[@]}"; do
        run_dir="${RUN_ROOT}/tps${tps}"
        
        echo "[*] Executando Benchmark Real: ${tps} TPS..."
        node src/bench_fabric_direct.js \
            --corpus "${CORPUS_PATH}" \
            --outdir "${run_dir}" \
            --tps "${tps}"
            
        sleep 10
    done

else
    echo "Erro: Modo desconhecido. Use 'embed' ou 'fabric'."
    echo "Exemplo: bash scripts/run_matrix.sh fabric"
    exit 1
fi


echo "====================================================="
echo "[*] Consolidando resultados no CSV..."

uv run python - <<'PY'
import csv
import json
import os
from pathlib import Path

matrix_id = os.environ.get("MATRIX_RUN_ID")
if not matrix_id:
    raise SystemExit("MATRIX_RUN_ID nao definido")

run_root = Path("results") / matrix_id
summary_path = run_root / "summary.csv"

if not run_root.exists():
    raise SystemExit(f"{run_root} nao encontrado")

rows = []
for run_file in run_root.rglob("run.jsonl"):
    with run_file.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            rows.append(json.loads(line))

fieldnames = [
    "run_id",
    "timestamp",
    "model_id",
    "max_length",
    "batch",
    "threads",
    "n_docs_total",
    "n_docs_measured",
    "p50_ms",
    "p95_ms",
    "docs_per_sec",
    "total_seconds_measured",
    "corpus_sha256",
    "embeddings_sha256",
]

with summary_path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") for key in fieldnames})

print(f"[✓] Relatório concluído: {summary_path}")
PY