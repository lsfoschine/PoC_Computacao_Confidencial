# Confidential Computing Benchmark PoC

[English](README.md) | [Português](README.pt-BR.md)

A reproducible CPU-only benchmark for comparing embedding workloads across
conventional and confidential-computing Linux environments. The benchmark uses
`BAAI/bge-m3`, versioned input datasets, content hashes, isolated warm-up data,
per-run environment metadata, and repeated measurements with 95% confidence
intervals.

## Requirements

- [uv](https://docs.astral.sh/uv/)

The Python version is pinned in `.python-version`; uv downloads it and creates the
virtual environment.

## Environment setup

```bash
uv python install
uv sync
```

For environments where user-level cache directories are restricted:

```bash
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv python install
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv sync
```

For authenticated Hugging Face downloads:

```bash
cp .env.example .env
```

Set `HUGGINGFACE_HUB_TOKEN` in `.env`. The file is ignored by Git.

## Versioned datasets

The repository contains two deterministic datasets:

- `data/corpus.jsonl`: 144 measured documents, with 24 documents for each target
  size: 256, 512, 1024, 2048, 4096, and 8192 approximate characters.
- `data/warmup.jsonl`: 32 deterministic, size-stratified documents used only to
  stabilize the same tokenization and encoding pipeline before measurement.

Validate both datasets before running:

```bash
./scripts/verify_corpus.sh
```

`run_all.sh` preserves and validates existing versioned datasets. It does not
regenerate them by default. To intentionally replace both datasets and hashes:

```bash
./scripts/run_all.sh --regenerate-corpus
```

## Single benchmark run

```bash
uv run python src/bench_embed.py \
  --corpus data/corpus.jsonl \
  --warmup-corpus data/warmup.jsonl \
  --batch 16 \
  --max-length 512 \
  --threads 8 \
  --warmup-docs 32
```

Measured throughput is calculated as:

```text
docs_per_sec = n_docs_measured / total_seconds_measured
```

Warm-up documents are never included in measured latency, throughput, CPU time,
or embeddings. The recorded p50/p95 values are amortized per-document latency
derived from each batch duration. Tail amplification is recorded as the
dimensionless ratio `p95_ms / p50_ms`.

## Repeated benchmark matrix

```bash
./scripts/run_matrix.sh
```

The default matrix runs three repetitions for every `max_length × batch`
combination. Override it with:

```bash
REPETITIONS=5 MAX_LENGTHS="256 512 1024" BATCHES="4 8" ./scripts/run_matrix.sh
```

The benchmark is provider-agnostic. Executors can use `MATRIX_RUN_ID` as an
operational label without changing the measurement:

```bash
MATRIX_RUN_ID=amd-sev-snp-01 ./scripts/run_matrix.sh
```

This label organizes artifacts; the observed platform evidence remains in each
run's `env.json`.

Outputs:

- `runs.csv`: one row per individual execution.
- `summary.csv`: means, standard deviation, and 95% confidence intervals grouped
  by model, maximum length, batch, threads, and dataset hashes, including tail
  amplification.

Use the confidence intervals when comparing machines. Small differences with
overlapping intervals should not be reported as conclusive gains.

## Complete runner

```bash
./scripts/run_all.sh --help
./scripts/run_all.sh
```

The complete runner installs the pinned Python version, synchronizes the uv
environment, validates the datasets, captures standalone environment metadata,
and executes the repeated matrix.

Useful options:

```text
--repetitions N
--regenerate-corpus
--skip-python
--skip-sync
--skip-dataset
--skip-env
--skip-matrix
```

## Run artifacts

Each benchmark run writes:

- `results/<run_id>/embeddings.npy`
- `results/<run_id>/embeddings.sha256`
- `results/<run_id>/run.jsonl`
- `results/<run_id>/env.json`

Matrix executions write nested runs under `results/<matrix_run_id>/`, plus
`runs.csv` and `summary.csv`.

The environment metadata is captured best-effort and includes CPU topology,
microcode, frequency policy, NUMA, affinity, memory, storage and mount details,
kernel and boot parameters, and confidential-computing evidence. Missing or
permission-restricted signals are represented explicitly in the JSON.

## Reproducing a comparison

For every machine:

1. Check out the same Git commit.
2. Run `./scripts/verify_corpus.sh`.
3. Confirm identical corpus and warm-up hashes.
4. Use the same matrix, thread count, and repetition count.
5. Compare `summary.csv` and retain every run directory as an audit artifact.

Do not commit `.env`, `results/`, or `reports/`.
