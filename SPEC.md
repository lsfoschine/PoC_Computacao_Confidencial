# Specification — CPU-only embedding benchmark

## Objective

Measure the CPU performance of `BAAI/bge-m3` across local, baseline-cloud, and
confidential-computing environments using identical, versioned inputs and
auditable run metadata.

## Inputs

- `data/corpus.jsonl`: deterministic measured corpus.
- `data/corpus.sha256`: measured corpus integrity manifest.
- `data/warmup.jsonl`: deterministic, size-stratified warm-up corpus.
- `data/warmup.sha256`: warm-up corpus integrity manifest.
- `uv.lock`: dependency lockfile used by every environment.

Warm-up data must use the same model, tokenizer, maximum length, batch size, and
thread configuration as the measured corpus. Warm-up data is not included in
embeddings or measured metrics.

## Method

1. Verify both dataset hashes.
2. Load the model on CPU and apply the configured thread limits.
3. Encode the separate warm-up corpus.
4. Measure the complete versioned corpus.
5. Repeat every matrix combination at least three times.
6. Retain raw run artifacts and aggregate results with 95% confidence intervals.

## Run metrics

- `n_docs_total` and `n_docs_measured`
- `total_seconds_measured`
- `docs_per_sec`
- amortized per-document `p50_ms` and `p95_ms`
- measured-window `cpu_user_s` and `cpu_system_s`
- process-wide `rss_peak_mb`

## Traceability

Every run records:

- corpus, warm-up corpus, embeddings, and uv lock hashes;
- model identifier and runtime parameters;
- Python version, Git commit, and dirty state;
- environment metadata covering CPU, memory, storage, kernel, NUMA, affinity,
  frequency policy, microcode, and confidential-computing signals.

## Statistical reporting

Machine comparisons must use repeated runs from `summary.csv`. Report means and
95% confidence intervals, plus the repetition count. Small differences with
overlapping intervals must not be presented as conclusive performance gains.
