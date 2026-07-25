import argparse
import csv
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path

T_CRITICAL_95 = {
    1: 12.706,
    2: 4.303,
    3: 3.182,
    4: 2.776,
    5: 2.571,
    6: 2.447,
    7: 2.365,
    8: 2.306,
    9: 2.262,
    10: 2.228,
    11: 2.201,
    12: 2.179,
    13: 2.160,
    14: 2.145,
    15: 2.131,
    16: 2.120,
    17: 2.110,
    18: 2.101,
    19: 2.093,
    20: 2.086,
    21: 2.080,
    22: 2.074,
    23: 2.069,
    24: 2.064,
    25: 2.060,
    26: 2.056,
    27: 2.052,
    28: 2.048,
    29: 2.045,
    30: 2.042,
}

RUN_FIELDS = [
    "run_id",
    "matrix_run_id",
    "matrix_repetition",
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
    "warmup_corpus_sha256",
    "embeddings_sha256",
]

SUMMARY_FIELDS = [
    "model_id",
    "max_length",
    "batch",
    "threads",
    "n_runs",
    "n_docs_total",
    "n_docs_measured",
    "docs_per_sec_mean",
    "docs_per_sec_stddev",
    "docs_per_sec_ci95",
    "p50_ms_mean",
    "p50_ms_ci95",
    "p95_ms_mean",
    "p95_ms_ci95",
    "total_seconds_measured_mean",
    "total_seconds_measured_ci95",
    "corpus_sha256",
    "warmup_corpus_sha256",
]


def load_rows(run_root: Path) -> list[dict]:
    rows = []
    for run_file in sorted(run_root.rglob("run.jsonl")):
        with run_file.open("r", encoding="utf-8") as handle:
            for line in handle:
                if line.strip():
                    rows.append(json.loads(line))
    if not rows:
        raise SystemExit(f"No run.jsonl records found under {run_root}")
    return rows


def mean_and_ci95(values) -> tuple[float, float, float]:
    numeric_values = [float(value) for value in values]
    mean = statistics.fmean(numeric_values)
    if len(numeric_values) < 2:
        return mean, 0.0, 0.0
    stddev = statistics.stdev(numeric_values)
    degrees_of_freedom = len(numeric_values) - 1
    critical = T_CRITICAL_95.get(degrees_of_freedom, 1.96)
    ci95 = critical * stddev / math.sqrt(len(numeric_values))
    return mean, stddev, ci95


def write_runs(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=RUN_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in RUN_FIELDS})


def write_summary(path: Path, rows: list[dict]) -> None:
    groups = defaultdict(list)
    for row in rows:
        key = (
            row.get("model_id"),
            row.get("max_length"),
            row.get("batch"),
            row.get("threads"),
            row.get("corpus_sha256"),
            row.get("warmup_corpus_sha256"),
        )
        groups[key].append(row)

    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=SUMMARY_FIELDS)
        writer.writeheader()
        for key, group in sorted(groups.items(), key=lambda item: item[0][1:4]):
            docs_mean, docs_stddev, docs_ci95 = mean_and_ci95(
                row["docs_per_sec"] for row in group
            )
            p50_mean, _, p50_ci95 = mean_and_ci95(row["p50_ms"] for row in group)
            p95_mean, _, p95_ci95 = mean_and_ci95(row["p95_ms"] for row in group)
            total_mean, _, total_ci95 = mean_and_ci95(
                row["total_seconds_measured"] for row in group
            )
            writer.writerow(
                {
                    "model_id": key[0],
                    "max_length": key[1],
                    "batch": key[2],
                    "threads": key[3],
                    "n_runs": len(group),
                    "n_docs_total": group[0].get("n_docs_total"),
                    "n_docs_measured": group[0].get("n_docs_measured"),
                    "docs_per_sec_mean": round(docs_mean, 6),
                    "docs_per_sec_stddev": round(docs_stddev, 6),
                    "docs_per_sec_ci95": round(docs_ci95, 6),
                    "p50_ms_mean": round(p50_mean, 3),
                    "p50_ms_ci95": round(p50_ci95, 3),
                    "p95_ms_mean": round(p95_mean, 3),
                    "p95_ms_ci95": round(p95_ci95, 3),
                    "total_seconds_measured_mean": round(total_mean, 6),
                    "total_seconds_measured_ci95": round(total_ci95, 6),
                    "corpus_sha256": key[4],
                    "warmup_corpus_sha256": key[5],
                }
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Aggregate benchmark run records.")
    parser.add_argument("--run-root", required=True, help="Matrix result directory")
    args = parser.parse_args()

    run_root = Path(args.run_root)
    if not run_root.exists():
        raise SystemExit(f"{run_root} not found")

    rows = load_rows(run_root)
    runs_path = run_root / "runs.csv"
    summary_path = run_root / "summary.csv"
    write_runs(runs_path, rows)
    write_summary(summary_path, rows)
    print(f"Wrote {runs_path}")
    print(f"Wrote {summary_path}")


if __name__ == "__main__":
    main()
