import argparse
import csv
import hashlib
import json
import platform
import socket
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def hash_file(path: Path) -> str | None:
    if not path.exists():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(*args: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", *args],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


def git_dirty() -> bool:
    status = git_output("status", "--porcelain")
    return bool(status) if status is not None else False


def count_jsonl_records(paths: list[Path]) -> int:
    total = 0
    for path in paths:
        with path.open("r", encoding="utf-8") as handle:
            total += sum(1 for line in handle if line.strip())
    return total


def count_csv_rows(path: Path) -> int:
    if not path.exists():
        return 0
    with path.open("r", encoding="utf-8", newline="") as handle:
        return sum(1 for _ in csv.DictReader(handle))


def write_manifest(path: Path, payload: dict) -> None:
    temporary_path = path.with_suffix(".json.tmp")
    temporary_path.write_text(
        json.dumps(payload, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary_path.replace(path)


def start_manifest(args: argparse.Namespace) -> None:
    run_root = Path(args.run_root)
    run_root.mkdir(parents=True, exist_ok=True)
    max_lengths = [int(value) for value in args.max_lengths.split()]
    batches = [int(value) for value in args.batches.split()]
    expected_configurations = len(max_lengths) * len(batches)
    expected_runs = expected_configurations * args.repetitions
    payload = {
        "schema_version": 1,
        "matrix_run_id": run_root.name,
        "status": "running",
        "started_at": utc_now(),
        "completed_at": None,
        "hostname": socket.gethostname(),
        "run_root": str(run_root),
        "command": args.command,
        "profile": {
            "model_id": args.model,
            "model_revision": args.model_revision,
            "max_lengths": max_lengths,
            "batches": batches,
            "threads": args.threads,
            "interop_threads": max(1, args.threads // 2),
            "warmup_docs": args.warmup_docs,
            "repetitions": args.repetitions,
        },
        "provenance": {
            "git_commit": git_output("rev-parse", "HEAD"),
            "git_dirty": git_dirty(),
            "python_version": platform.python_version(),
            "uv_lock_sha256": hash_file(Path("uv.lock")),
        },
        "inputs": {
            "corpus_path": args.corpus,
            "corpus_sha256": hash_file(Path(args.corpus)),
            "warmup_corpus_path": args.warmup_corpus,
            "warmup_corpus_sha256": hash_file(Path(args.warmup_corpus)),
        },
        "expected": {
            "configurations": expected_configurations,
            "runs": expected_runs,
            "runs_csv_rows": expected_runs,
            "summary_csv_rows": expected_configurations,
            "per_run_env_files": expected_runs,
            "embedding_files": expected_runs,
            "embedding_hash_files": expected_runs,
        },
        "actual": None,
    }
    write_manifest(run_root / "manifest.json", payload)


def complete_manifest(args: argparse.Namespace) -> None:
    run_root = Path(args.run_root)
    manifest_path = run_root / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"{manifest_path} not found")
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    run_files = sorted(run_root.rglob("run.jsonl"))
    actual = {
        "run_directories": len(run_files),
        "run_records": count_jsonl_records(run_files),
        "runs_csv_rows": count_csv_rows(run_root / "runs.csv"),
        "summary_csv_rows": count_csv_rows(run_root / "summary.csv"),
        "per_run_env_files": len(list(run_root.rglob("env.json"))),
        "embedding_files": len(list(run_root.rglob("embeddings.npy"))),
        "embedding_hash_files": len(list(run_root.rglob("embeddings.sha256"))),
        "pre_run_environment": (run_root / "env.before.json").exists(),
        "run_log": (run_root / "run.log").exists(),
    }
    expected = payload["expected"]
    checks = {
        "run_directories": expected["runs"],
        "run_records": expected["runs"],
        "runs_csv_rows": expected["runs_csv_rows"],
        "summary_csv_rows": expected["summary_csv_rows"],
        "per_run_env_files": expected["per_run_env_files"],
        "embedding_files": expected["embedding_files"],
        "embedding_hash_files": expected["embedding_hash_files"],
    }
    mismatches = {
        field: {"expected": expected_value, "actual": actual[field]}
        for field, expected_value in checks.items()
        if actual[field] != expected_value
    }
    if mismatches:
        raise SystemExit(f"Incomplete matrix artifacts: {json.dumps(mismatches)}")
    payload["status"] = "completed"
    payload["completed_at"] = utc_now()
    payload["actual"] = actual
    write_manifest(manifest_path, payload)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create or complete a matrix manifest.")
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--status", required=True, choices=("start", "complete"))
    parser.add_argument("--command", default=None)
    parser.add_argument("--model")
    parser.add_argument("--model-revision")
    parser.add_argument("--max-lengths")
    parser.add_argument("--batches")
    parser.add_argument("--threads", type=int)
    parser.add_argument("--warmup-docs", type=int)
    parser.add_argument("--repetitions", type=int)
    parser.add_argument("--corpus", default="data/corpus.jsonl")
    parser.add_argument("--warmup-corpus", default="data/warmup.jsonl")
    args = parser.parse_args()

    if args.status == "start":
        required = (
            "model",
            "model_revision",
            "max_lengths",
            "batches",
            "threads",
            "warmup_docs",
            "repetitions",
        )
        missing = [field for field in required if getattr(args, field) is None]
        if missing:
            raise SystemExit(f"Missing start fields: {', '.join(missing)}")
        start_manifest(args)
    else:
        complete_manifest(args)


if __name__ == "__main__":
    main()
